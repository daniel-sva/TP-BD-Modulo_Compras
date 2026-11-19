USE modulo_compras;
DELIMITER //

-- --------------------------------------------------------------------------------
/* 
  INICIO TRIGGERS ORDENES_DE_PAGO
*/
-- --------------------------------------------------------------------------------

/*
    BEFORE INSERT
    - Valida que la orden de pago no sea posterior a la fecha actual.
    - Fuerza a que nazca la orden como borrador vacío.
*/
DROP TRIGGER IF EXISTS trg_ordenes_de_pago_before_insert //
CREATE TRIGGER trg_ordenes_de_pago_before_insert
BEFORE INSERT ON ORDENES_DE_PAGO
FOR EACH ROW
BEGIN
    IF NEW.fecha > CURRENT_DATE() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La fecha de orden de pago no puede ser posterior a la fecha actual.';
    END IF;
    SET NEW.monto_total = 0.00;
    SET NEW.confirmado = FALSE;
END //


/*
    AFTER INSERT
    - Registra en BITACORA. 
*/
DROP TRIGGER IF EXISTS trg_ordenes_de_pago_after_insert //
CREATE TRIGGER trg_ordenes_de_pago_after_insert
AFTER INSERT ON ORDENES_DE_PAGO
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
    nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
    'ORDENES_DE_PAGO', 'INSERT', 4, NOW(),
    JSON_OBJECT('NULL', null),
    JSON_OBJECT('id',           NEW.id,
                'id_proveedor', NEW.id_proveedor,
                'fecha',        NEW.fecha,
                'monto_total',  NEW.monto_total,
                'confirmado',   NEW.confirmado
               )
  );
END //


/*
    BEFORE UPDATE
    - Valida que la fecha de la orden no sea posterior a la fecha actual.
    - Bloquea modificaciones si la orden ya está confirmada (salvo que se revierta a borrador).
    - Impide alterar la fecha o el proveedor si la orden ya fue confirmada, o cambiar el proveedor si ya tiene facturas cargadas.
    - Al confirmar (FALSE -> TRUE): verifica que existan detalles, que cuadren los totales de facturas y formas de pago, que las facturas sean válidas y fija el monto_total definitivo.
    - Al revertir/anular (TRUE -> FALSE): verifica que el proveedor tenga línea de crédito disponible para reabsorber la deuda.
*/
DROP TRIGGER IF EXISTS trg_ordenes_de_pago_before_update //
CREATE TRIGGER trg_ordenes_de_pago_before_update
BEFORE UPDATE ON ORDENES_DE_PAGO
FOR EACH ROW
BEGIN
    DECLARE v_monto_total_facturas DECIMAL(15,2);
    DECLARE v_monto_total_formas DECIMAL(15,2);
    DECLARE v_existe_factura BOOLEAN;
    DECLARE v_facturas_invalidas INT;
    DECLARE v_saldo_credito DECIMAL(15,2) DEFAULT 0.00;

    IF NEW.fecha > CURRENT_DATE() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La fecha de la orden de pago no puede ser posterior a la fecha actual.';
    END IF;

    IF OLD.confirmado = TRUE AND NEW.confirmado = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se puede modificar una orden de pago que ya ha sido confirmada.';
    END IF;

    -- Son inmutables la fecha y proveedor una vez confirmada (incluso al revertir) , para modificarlos primero se anula orden
    IF OLD.confirmado = TRUE AND (NEW.fecha <> OLD.fecha OR NEW.id_proveedor <> OLD.id_proveedor) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se puede modificar la fecha ni el proveedor de una orden de pago confirmada.';
    END IF;

    -- Es inmutable el proveedor si ya hay facturas (incluso en estado borrador)
    SELECT EXISTS (SELECT 1 FROM ORDEN_DE_PAGO_FACTURAS WHERE id_orden_de_pago = OLD.id) INTO v_existe_factura;
    IF v_existe_factura = TRUE AND (NEW.id_proveedor <> OLD.id_proveedor) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se puede cambiar el proveedor porque ya existen facturas cargadas en esta orden.';
    END IF;

    -- TRANSICION DE BORRADOR A CONFIRMADA
    IF OLD.confirmado = FALSE AND NEW.confirmado = TRUE THEN
        
        -- Calcular totales en facturas y formas (detalles de orden)
        SELECT COALESCE(SUM(monto_pagado), 0.00) INTO v_monto_total_facturas
        FROM ORDEN_DE_PAGO_FACTURAS WHERE id_orden_de_pago = OLD.id;

        SELECT COALESCE(SUM(monto_pagado), 0.00) INTO v_monto_total_formas
        FROM ORDEN_DE_PAGO_FORMAS WHERE id_orden_de_pago = OLD.id;

        -- Validar que la orden no está vacía
        IF v_monto_total_facturas <= 0.00 OR v_monto_total_formas <= 0.00 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: La orden de pago no tiene detalles cargados o sus montos son cero.';
        END IF;

        -- Validar igualdad de montos
        IF v_monto_total_facturas <> v_monto_total_formas THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No se puede confirmar. El total de facturas a pagar no coincide con el total de formas de pago.';
        END IF;

        -- Validar facturas (Cumplir con: mismo proveedor, estar pendiente/vencida, tener saldo suficiente)
        SELECT COUNT(*) INTO v_facturas_invalidas
        FROM ORDEN_DE_PAGO_FACTURAS opf
        INNER JOIN COMPRAS_CABECERA cc ON opf.id_compra = cc.id
        WHERE opf.id_orden_de_pago = OLD.id
          AND (cc.id_proveedor <> NEW.id_proveedor 
               OR cc.id_estado NOT IN (1, 3) 
               OR cc.saldo_factura < opf.monto_pagado);

        IF v_facturas_invalidas > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Existen facturas inválidas (pertenecen a otro proveedor, ya están pagadas/anuladas o el saldo es insuficiente).';
        END IF;

        SET NEW.monto_total = v_monto_total_facturas;
    END IF;

    -- TRANSICION DE CONFIRMADA A BORRADOR/ANULADA
    IF OLD.confirmado = TRUE AND NEW.confirmado = FALSE THEN
        
        -- Validar que el proveedor tenga linea de credito suficiente para reabsorber la deuda de la factura.
        SELECT saldo_linea_credito INTO v_saldo_credito
        FROM PROVEEDORES WHERE id = OLD.id_proveedor;

        IF v_saldo_credito < OLD.monto_total THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: El proveedor no tiene suficiente línea de crédito disponible para revertir/anular esta orden.';
        END IF;

    END IF;
END //


/*
    AFTER UPDATE
    - Al confirmar (FALSE -> TRUE): descuenta el monto_pagado del saldo_factura en COMPRAS_CABECERA.
    - Al revertir/anular (TRUE -> FALSE): restituye el monto_pagado al saldo_factura en COMPRAS_CABECERA.
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_ordenes_de_pago_after_update //
CREATE TRIGGER trg_ordenes_de_pago_after_update
AFTER UPDATE ON ORDENES_DE_PAGO
FOR EACH ROW
BEGIN
    -- Aplicar pagos (false -> true)
    IF OLD.confirmado = FALSE AND NEW.confirmado = TRUE THEN
        UPDATE COMPRAS_CABECERA cc
        INNER JOIN ORDEN_DE_PAGO_FACTURAS opf ON cc.id = opf.id_compra
        SET cc.saldo_factura = cc.saldo_factura - opf.monto_pagado
        WHERE opf.id_orden_de_pago = NEW.id;
    END IF;

    -- Revertir pagos (true -> false)
    IF OLD.confirmado = TRUE AND NEW.confirmado = FALSE THEN
        UPDATE COMPRAS_CABECERA cc
        INNER JOIN ORDEN_DE_PAGO_FACTURAS opf ON cc.id = opf.id_compra
        SET cc.saldo_factura = cc.saldo_factura + opf.monto_pagado
        WHERE opf.id_orden_de_pago = NEW.id;
    END IF;

    -- AUDITORÍA
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'ORDENES_DE_PAGO', 'UPDATE', 4, NOW(),
        JSON_OBJECT('id',           OLD.id,
                    'id_proveedor', OLD.id_proveedor,
                    'fecha',        OLD.fecha,
                    'monto_total',  OLD.monto_total,
                    'confirmado',   OLD.confirmado),
        JSON_OBJECT('id',           NEW.id,
                    'id_proveedor', NEW.id_proveedor,
                    'fecha',        NEW.fecha,
                    'monto_total',  NEW.monto_total,
                    'confirmado',   NEW.confirmado)
    );
END //


/*
    BEFORE DELETE
    - Bloquea la eliminación si la orden de pago ya está confirmada.
    - Elimina primero los detalles asociados (facturas y formas).
*/
DROP TRIGGER IF EXISTS trg_ordenes_de_pago_before_delete //
CREATE TRIGGER trg_ordenes_de_pago_before_delete
BEFORE DELETE ON ORDENES_DE_PAGO
FOR EACH ROW
BEGIN
    -- Bloquear si está confirmada
    IF OLD.confirmado = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se puede eliminar una orden de pago confirmada. Debe revertirla a borrador (desconfirmar) primero.';
    END IF;

    -- Borrado en cascada de los detalles si es borrador
    DELETE FROM ORDEN_DE_PAGO_FACTURAS WHERE id_orden_de_pago = OLD.id;
    DELETE FROM ORDEN_DE_PAGO_FORMAS WHERE id_orden_de_pago = OLD.id;
END //


/*
    AFTER DELETE
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_ordenes_de_pago_after_delete //
CREATE TRIGGER trg_ordenes_de_pago_after_delete
AFTER DELETE ON ORDENES_DE_PAGO
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'ORDENES_DE_PAGO', 'DELETE', 4, NOW(),
        JSON_OBJECT('id',           OLD.id,
                    'id_proveedor', OLD.id_proveedor,
                    'fecha',        OLD.fecha,
                    'monto_total',  OLD.monto_total,
                    'confirmado',   OLD.confirmado),
        JSON_OBJECT('NULL', null)
    );
END //


-- --------------------------------------------------------------------------------
/* 
  INICIO TRIGGERS ORDEN_DE_PAGO_FACTURAS
*/
-- --------------------------------------------------------------------------------


/*
    BEFORE INSERT
    - Verifica que la orden de pago esté en estado borrador.
    - Valida que la factura pertenezca al mismo proveedor de la orden de pago.
    - Verifica que la factura sea a crédito y esté en estado PENDIENTE (1) o VENCIDA (3).
    - Valida que el monto_pagado no supere el saldo_factura pendiente.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_facturas_before_insert //
CREATE TRIGGER trg_orden_de_pago_facturas_before_insert
BEFORE INSERT ON ORDEN_DE_PAGO_FACTURAS
FOR EACH ROW
BEGIN
    DECLARE v_confirmado BOOLEAN;
    DECLARE v_id_proveedor_orden INT UNSIGNED;
    DECLARE v_id_proveedor_compra INT UNSIGNED;
    DECLARE v_a_credito BOOLEAN;
    DECLARE v_id_estado INT UNSIGNED;
    DECLARE v_saldo_factura DECIMAL(15,2);

    SELECT confirmado, id_proveedor 
    INTO v_confirmado, v_id_proveedor_orden
    FROM ORDENES_DE_PAGO 
    WHERE id = NEW.id_orden_de_pago;

    IF v_confirmado = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden agregar facturas a una orden de pago que ya ha sido confirmada.';
    END IF;

    SELECT id_proveedor, a_credito, id_estado, saldo_factura
    INTO v_id_proveedor_compra, v_a_credito, v_id_estado, v_saldo_factura
    FROM COMPRAS_CABECERA 
    WHERE id = NEW.id_compra;

    IF v_id_proveedor_compra <> v_id_proveedor_orden THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La factura seleccionada no pertenece al proveedor de la orden de pago.';
    END IF;

    IF v_a_credito = FALSE OR v_id_estado NOT IN (1, 3) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Solo se pueden pagar facturas a crédito en estado PENDIENTE o VENCIDA.';
    END IF;

    IF NEW.monto_pagado > v_saldo_factura THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El monto a pagar supera el saldo pendiente de la factura.';
    END IF;
END //


/*
    AFTER INSERT
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_facturas_after_insert //
CREATE TRIGGER trg_orden_de_pago_facturas_after_insert
AFTER INSERT ON ORDEN_DE_PAGO_FACTURAS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'ORDEN_DE_PAGO_FACTURAS', 'INSERT', 4, NOW(),
        JSON_OBJECT('NULL', null),
        JSON_OBJECT('id',               NEW.id,
                    'id_orden_de_pago', NEW.id_orden_de_pago,
                    'id_compra',        NEW.id_compra,
                    'monto_pagado',     NEW.monto_pagado)
    );
END //


/*
    BEFORE UPDATE
    - Mantiene inmutables id_orden_de_pago e id_compra.
    - Verifica que la orden de pago siga en estado borrador.
    - Verifica que la factura siga vigente (PENDIENTE o VENCIDA) y que el nuevo monto_pagado no supere su saldo_factura.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_facturas_before_update //
CREATE TRIGGER trg_orden_de_pago_facturas_before_update
BEFORE UPDATE ON ORDEN_DE_PAGO_FACTURAS
FOR EACH ROW
BEGIN
    DECLARE v_confirmado BOOLEAN;
    DECLARE v_id_estado INT UNSIGNED;
    DECLARE v_saldo_factura DECIMAL(15,2);

    SET NEW.id_orden_de_pago = OLD.id_orden_de_pago;
    SET NEW.id_compra        = OLD.id_compra;

    SELECT confirmado INTO v_confirmado
    FROM ORDENES_DE_PAGO
    WHERE id = OLD.id_orden_de_pago;

    IF v_confirmado = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden modificar los montos de una orden de pago que ya ha sido confirmada.';
    END IF;

    SELECT id_estado, saldo_factura
    INTO v_id_estado, v_saldo_factura
    FROM COMPRAS_CABECERA
    WHERE id = OLD.id_compra;

    IF v_id_estado NOT IN (1, 3) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La factura asociada ya no se encuentra en estado PENDIENTE o VENCIDA.';
    END IF;

    IF NEW.monto_pagado > v_saldo_factura THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El nuevo monto a pagar supera el saldo pendiente de la factura.';
    END IF;
END //


/*
    AFTER UPDATE
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_facturas_after_update //
CREATE TRIGGER trg_orden_de_pago_facturas_after_update
AFTER UPDATE ON ORDEN_DE_PAGO_FACTURAS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'ORDEN_DE_PAGO_FACTURAS', 'UPDATE', 4, NOW(),
        JSON_OBJECT('id',               OLD.id,
                    'id_orden_de_pago', OLD.id_orden_de_pago,
                    'id_compra',        OLD.id_compra,
                    'monto_pagado',     OLD.monto_pagado),
        JSON_OBJECT('id',               NEW.id,
                    'id_orden_de_pago', NEW.id_orden_de_pago,
                    'id_compra',        NEW.id_compra,
                    'monto_pagado',     NEW.monto_pagado)
    );
END //


/*
    BEFORE DELETE
    - Verifica que la cabecera se encuentre en estado borrador para poder eliminar.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_facturas_before_delete //
CREATE TRIGGER trg_orden_de_pago_facturas_before_delete
BEFORE DELETE ON ORDEN_DE_PAGO_FACTURAS
FOR EACH ROW
BEGIN
    DECLARE v_confirmado BOOLEAN;

    SELECT confirmado INTO v_confirmado
    FROM ORDENES_DE_PAGO
    WHERE id = OLD.id_orden_de_pago;

    IF v_confirmado = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden eliminar facturas de una orden de pago que ya ha sido confirmada.';
    END IF;
END //


/*
    AFTER DELETE
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_facturas_after_delete //
CREATE TRIGGER trg_orden_de_pago_facturas_after_delete
AFTER DELETE ON ORDEN_DE_PAGO_FACTURAS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'ORDEN_DE_PAGO_FACTURAS', 'DELETE', 4, NOW(),
        JSON_OBJECT('id',               OLD.id,
                    'id_orden_de_pago', OLD.id_orden_de_pago,
                    'id_compra',        OLD.id_compra,
                    'monto_pagado',     OLD.monto_pagado),
        JSON_OBJECT('NULL', null)
    );
END //


-- --------------------------------------------------------------------------------
/* 
  INICIO TRIGGERS ORDEN_DE_PAGO_FORMAS
*/
-- --------------------------------------------------------------------------------


/*
    BEFORE INSERT
    - Verifica que la orden de pago cabecera se encuentre en estado borrador.
    - Normaliza cadenas vacías en el campo referencia a NULL.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_formas_before_insert //
CREATE TRIGGER trg_orden_de_pago_formas_before_insert
BEFORE INSERT ON ORDEN_DE_PAGO_FORMAS
FOR EACH ROW
BEGIN
    DECLARE v_confirmado BOOLEAN;

    SELECT confirmado INTO v_confirmado
    FROM ORDENES_DE_PAGO
    WHERE id = NEW.id_orden_de_pago;

    IF v_confirmado = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden agregar formas de pago a una orden que ya ha sido confirmada.';
    END IF;

    SET NEW.referencia = NULLIF(TRIM(NEW.referencia), '');
END //


/*
    AFTER INSERT
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_formas_after_insert //
CREATE TRIGGER trg_orden_de_pago_formas_after_insert
AFTER INSERT ON ORDEN_DE_PAGO_FORMAS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'ORDEN_DE_PAGO_FORMAS', 'INSERT', 4, NOW(),
        JSON_OBJECT('NULL', null),
        JSON_OBJECT('id',               NEW.id,
                    'id_orden_de_pago', NEW.id_orden_de_pago,
                    'id_forma_de_pago', NEW.id_forma_de_pago,
                    'monto_pagado',     NEW.monto_pagado,
                    'referencia',       NEW.referencia)
    );
END //


/*
    BEFORE UPDATE
    - Mantiene inmutable la referencia a la cabecera de la orden de pago.
    - Verifica que la orden de pago cabecera siga en estado borrador.
    - Normaliza espacios en blanco en el campo referencia a NULL.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_formas_before_update //
CREATE TRIGGER trg_orden_de_pago_formas_before_update
BEFORE UPDATE ON ORDEN_DE_PAGO_FORMAS
FOR EACH ROW
BEGIN
    DECLARE v_confirmado BOOLEAN;

    SET NEW.id_orden_de_pago = OLD.id_orden_de_pago;

    SELECT confirmado INTO v_confirmado
    FROM ORDENES_DE_PAGO
    WHERE id = OLD.id_orden_de_pago;

    IF v_confirmado = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden modificar las formas de pago de una orden que ya ha sido confirmada.';
    END IF;

    SET NEW.referencia = NULLIF(TRIM(NEW.referencia), '');
END //


/*
    AFTER UPDATE
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_formas_after_update //
CREATE TRIGGER trg_orden_de_pago_formas_after_update
AFTER UPDATE ON ORDEN_DE_PAGO_FORMAS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'ORDEN_DE_PAGO_FORMAS', 'UPDATE', 4, NOW(),
        JSON_OBJECT('id',               OLD.id,
                    'id_orden_de_pago', OLD.id_orden_de_pago,
                    'id_forma_de_pago', OLD.id_forma_de_pago,
                    'monto_pagado',     OLD.monto_pagado,
                    'referencia',       OLD.referencia),
        JSON_OBJECT('id',               NEW.id,
                    'id_orden_de_pago', NEW.id_orden_de_pago,
                    'id_forma_de_pago', NEW.id_forma_de_pago,
                    'monto_pagado',     NEW.monto_pagado,
                    'referencia',       NEW.referencia)
    );
END //


/*
    BEFORE DELETE
    - Verifica que la orden de pago cabecera se encuentre en estado borrador para poder eliminar.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_formas_before_delete //
CREATE TRIGGER trg_orden_de_pago_formas_before_delete
BEFORE DELETE ON ORDEN_DE_PAGO_FORMAS
FOR EACH ROW
BEGIN
    DECLARE v_confirmado BOOLEAN;

    SELECT confirmado INTO v_confirmado
    FROM ORDENES_DE_PAGO
    WHERE id = OLD.id_orden_de_pago;

    IF v_confirmado = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden eliminar formas de pago de una orden que ya ha sido confirmada.';
    END IF;
END //


/*
    AFTER DELETE
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_orden_de_pago_formas_after_delete //
CREATE TRIGGER trg_orden_de_pago_formas_after_delete
AFTER DELETE ON ORDEN_DE_PAGO_FORMAS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'ORDEN_DE_PAGO_FORMAS', 'DELETE', 4, NOW(),
        JSON_OBJECT('id',               OLD.id,
                    'id_orden_de_pago', OLD.id_orden_de_pago,
                    'id_forma_de_pago', OLD.id_forma_de_pago,
                    'monto_pagado',     OLD.monto_pagado,
                    'referencia',       OLD.referencia),
        JSON_OBJECT('NULL', null)
    );
END //


DELIMITER ;