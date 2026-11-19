USE modulo_compras;
-- tamanhos variables de msg sqlstate pueden superar limite

-- preguntar: revertir ordenes de pago para anular facturas

-- Flujo: registrar productos -> crear cabecera (monto y saldo mutables, no borrable) -> registrar detalles (inmutables, no borrables)

DELIMITER //
-- --------------------------------------------------------------------------------
/* 
  INICIO TRIGGERS COMPRAS_CABECERA
*/
-- --------------------------------------------------------------------------------

/*
    BEFORE INSERT
    - Verifica que sea una factura de hoy o antes.
    - Inicializa el monto total y el saldo de la factura en Gs.0
    - Si es a crédito entra en estado PENDIENTE si aún no se vence, sino VENCIDA.
    - Si es al contado entra en estado PAGADA y Fecha de vencimiento = Fecha de compra.
*/
DROP TRIGGER IF EXISTS trg_compras_cabecera_before_insert //
CREATE TRIGGER trg_compras_cabecera_before_insert
BEFORE INSERT ON COMPRAS_CABECERA
FOR EACH ROW
BEGIN
    IF NEW.fecha_compra > CURRENT_DATE() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La fecha de compra no puede ser posterior a la fecha actual.';
    END IF;

    SET NEW.monto_total = 0.00;
    SET NEW.saldo_factura = 0.00;

    IF NEW.a_credito = TRUE THEN
        IF NEW.fecha_vencimiento < CURRENT_DATE() THEN
            SET NEW.id_estado = 3; -- VENCIDA
        ELSE
            SET NEW.id_estado = 1; -- PENDIENTE
        END IF;
    ELSE
        SET NEW.id_estado = 2; -- PAGADA
        SET NEW.fecha_vencimiento = NEW.fecha_compra;
    END IF;
END //


/*
    AFTER INSERT
    - Registro de Bitácora para INSERT en COMPRAS_CABECERA.
*/
DROP TRIGGER IF EXISTS trg_compras_cabecera_after_insert //
CREATE TRIGGER trg_compras_cabecera_after_insert
AFTER INSERT ON COMPRAS_CABECERA
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
    nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
    'COMPRAS_CABECERA', 'INSERT', 2, NOW(),
    JSON_OBJECT('NULL', null),
    JSON_OBJECT('id',                   NEW.id,
                'numero_factura',       NEW.numero_factura,
                'timbrado',             NEW.timbrado,
                'id_proveedor',         NEW.id_proveedor,
                'fecha_compra',         NEW.fecha_compra,
                'fecha_vencimiento',    NEW.fecha_vencimiento,
                'a_credito',            NEW.a_credito,
                'id_deposito_ingreso',  NEW.id_deposito_ingreso,
                'monto_total',          NEW.monto_total,
                'saldo_factura',        NEW.saldo_factura,
                'id_estado',            NEW.id_estado
               )
  );
END //


/*
    BEFORE UPDATE
    - No permite modificar ningún dato excepto monto_total, saldo_factura e id_estado.
    - No permite anular facturas pagadas o ya anuladas.
    - Gestiona anulación de factura: Hay pagos parciales o stock consumido -> falla, sino -> anula y saldo = 0.
    - Cancela modificación de factura a crédito si se supera deuda con proveedor. 
    - Actualiza estado según fecha de vencimiento y nuevos monto total y saldo de factura.
*/
DROP TRIGGER IF EXISTS trg_compras_cabecera_before_update //
CREATE TRIGGER trg_compras_cabecera_before_update
BEFORE UPDATE ON COMPRAS_CABECERA
FOR EACH ROW
BEGIN
    DECLARE v_saldo_disponible DECIMAL(15,2);
    DECLARE v_incremento_saldo DECIMAL(15,2);

    SET NEW.numero_factura      = OLD.numero_factura;
    SET NEW.timbrado            = OLD.timbrado;
    SET NEW.id_proveedor        = OLD.id_proveedor;
    SET NEW.fecha_compra        = OLD.fecha_compra;
    SET NEW.fecha_vencimiento   = OLD.fecha_vencimiento;
    SET NEW.a_credito           = OLD.a_credito;
    SET NEW.id_deposito_ingreso = OLD.id_deposito_ingreso;

    IF OLD.id_estado = 4 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se puede modificar una factura ANULADA.';
    END IF;

    -- Solo se puede anular facturas a credito que no tengan aun pagos parciales y cuenten con el stock suficiente para devolver
    IF NEW.id_estado = 4 THEN
        
        IF OLD.id_estado = 2 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No se puede anular una factura PAGADA.';
        END IF;

        IF OLD.a_credito = TRUE AND OLD.saldo_factura < OLD.monto_total THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No se puede anular la factura porque ya posee pagos parciales.';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM COMPRAS_DETALLE cd
                INNER JOIN STOCK_DEPOSITO sd 
                ON sd.id_producto = cd.id_producto AND sd.id_deposito = OLD.id_deposito_ingreso
            WHERE cd.id_compra = OLD.id AND sd.cantidad < cd.cantidad -- El stock actual es menor al que se intenta devolver
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No se puede anular la factura. Parte de la mercadería ingresada ya fue vendida, transferida o consumida.';
        END IF;

        SET NEW.saldo_factura = 0.00; -- Las facturas anuladas tienen como regla saldo_factura = 0
    
    -- Si no se quiere anular la factura
    ELSE
        -- Si es al contado
        IF NEW.a_credito = FALSE THEN
            SET NEW.saldo_factura = 0.00;
            SET NEW.id_estado = 2; -- PAGADA
        -- Si es a credito
        ELSE
            IF NEW.saldo_factura > OLD.saldo_factura THEN
                SET v_incremento_saldo = NEW.saldo_factura - OLD.saldo_factura;

                SELECT saldo_linea_credito INTO v_saldo_disponible
                FROM PROVEEDORES WHERE id = NEW.id_proveedor;

                IF v_incremento_saldo > v_saldo_disponible THEN
                    SIGNAL SQLSTATE '45000' 
                    SET MESSAGE_TEXT = 'Error: El incremento en el saldo de la factura supera el crédito disponible del proveedor.';
                END IF;
            END IF;

            IF NEW.monto_total > 0.00 AND NEW.saldo_factura = 0.00 THEN
                SET NEW.id_estado = 2; -- PAGADA
            ELSEIF NEW.fecha_vencimiento < CURRENT_DATE() THEN
                SET NEW.id_estado = 3; -- VENCIDA
            ELSE
                SET NEW.id_estado = 1; -- PENDIENTE
            END IF;
        END IF;

    END IF;
END //


/*
    AFTER UPDATE
    - Si se anula factura a crédito se restituye crédito al proveedor y resta del stock sus productos.
    - Si no se anula se actualiza la línea de crédito.
    - Registro de Bitácora para UPDATE en COMPRAS_CABECERA.
*/
DROP TRIGGER IF EXISTS trg_compras_cabecera_after_update //
CREATE TRIGGER trg_compras_cabecera_after_update
AFTER UPDATE ON COMPRAS_CABECERA
FOR EACH ROW
BEGIN
    IF NEW.id_estado = 4 AND OLD.id_estado IN (1,3) THEN
        UPDATE STOCK_DEPOSITO sd INNER JOIN COMPRAS_DETALLE cd ON sd.id_producto = cd.id_producto
        SET sd.cantidad = sd.cantidad - cd.cantidad
        WHERE cd.id_compra = OLD.id AND sd.id_deposito = OLD.id_deposito_ingreso;

        IF OLD.a_credito = TRUE THEN
            UPDATE PROVEEDORES 
            SET saldo_linea_credito = saldo_linea_credito + OLD.monto_total
            WHERE id = OLD.id_proveedor;
        END IF;

    ELSEIF NEW.a_credito = TRUE AND OLD.saldo_factura <> NEW.saldo_factura THEN
        UPDATE PROVEEDORES 
        SET saldo_linea_credito = saldo_linea_credito + (OLD.saldo_factura - NEW.saldo_factura)
        WHERE id = NEW.id_proveedor;
    END IF;

    INSERT INTO BITACORA (
    nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
    'COMPRAS_CABECERA', 'UPDATE', 2, NOW(),
    JSON_OBJECT('id',                   OLD.id,
                'numero_factura',       OLD.numero_factura,
                'timbrado',             OLD.timbrado,
                'id_proveedor',         OLD.id_proveedor,
                'fecha_compra',         OLD.fecha_compra,
                'fecha_vencimiento',    OLD.fecha_vencimiento,
                'a_credito',            OLD.a_credito,
                'id_deposito_ingreso',  OLD.id_deposito_ingreso,
                'monto_total',          OLD.monto_total,
                'saldo_factura',        OLD.saldo_factura,
                'id_estado',            OLD.id_estado
                ),
    JSON_OBJECT('id',                   NEW.id,
                'numero_factura',       NEW.numero_factura,
                'timbrado',             NEW.timbrado,
                'id_proveedor',         NEW.id_proveedor,
                'fecha_compra',         NEW.fecha_compra,
                'fecha_vencimiento',    NEW.fecha_vencimiento,
                'a_credito',            NEW.a_credito,
                'id_deposito_ingreso',  NEW.id_deposito_ingreso,
                'monto_total',          NEW.monto_total,
                'saldo_factura',        NEW.saldo_factura,
                'id_estado',            NEW.id_estado
                )
  );
END //


/*
    BEFORE DELETE
    - Cancela cualquier intento de borrado. Solo se permite borrado lógico.
*/
DROP TRIGGER IF EXISTS trg_compras_cabecera_before_delete //
CREATE TRIGGER trg_compras_cabecera_before_delete
BEFORE DELETE ON COMPRAS_CABECERA
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Error: Las facturas de compra no se pueden eliminar físicamente. Utilice la anulación (baja lógica).';
END //


/*
    AFTER DELETE
    - No realiza nada.
*/


-- --------------------------------------------------------------------------------
/* 
  INICIO TRIGGERS COMPRAS_DETALLE
*/
-- --------------------------------------------------------------------------------

/*
    BEFORE INSERT
    - Cancela el INSERT si la factura está ANULADA o si es a crédito con pagos ya aplicados.
    - Autocompleta IVA del producto.
    - Calcula subtotal.
*/
DROP TRIGGER IF EXISTS trg_compras_detalle_before_insert //
CREATE TRIGGER trg_compras_detalle_before_insert
BEFORE INSERT ON COMPRAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_id_estado TINYINT UNSIGNED;
    DECLARE v_a_credito BOOLEAN;
    DECLARE v_monto_total DECIMAL(15,2);
    DECLARE v_saldo_factura DECIMAL(15,2);
    DECLARE v_porcentaje_iva NUMERIC(5,2);

    SELECT id_estado, a_credito, monto_total, saldo_factura
    INTO v_id_estado, v_a_credito, v_monto_total, v_saldo_factura
    FROM COMPRAS_CABECERA c WHERE c.id = NEW.id_compra;

    IF v_id_estado = 4 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden agregar detalles a una factura ANULADA.';
    END IF;

    IF v_a_credito = TRUE AND (v_id_estado = 2 OR v_saldo_factura < v_monto_total) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden agregar detalles a una factura a crédito que ya posee pagos registrados.';
    END IF;
    
    SELECT porcentaje_iva INTO v_porcentaje_iva FROM PRODUCTOS p WHERE p.id = NEW.id_producto LIMIT 1;
    IF v_porcentaje_iva IS NOT NULL THEN
        SET NEW.porcentaje_iva = v_porcentaje_iva;
    END IF;

    SET NEW.subtotal = NEW.cantidad * NEW.costo_unitario;
END //


/*
    AFTER INSERT
    - Agrega al stock los productos.
    - Actualiza el último costo unitario si corresponde a la compra válida más reciente.
    - Actualiza monto_total y saldo_factura de la cabecera.
    - Registra en BITACORA.
*/

DROP TRIGGER IF EXISTS trg_compras_detalle_after_insert //
CREATE TRIGGER trg_compras_detalle_after_insert
AFTER INSERT ON COMPRAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_id_deposito INT UNSIGNED;
    DECLARE v_a_credito BOOLEAN;
    DECLARE v_ultima_compra INT UNSIGNED;

    SELECT id_deposito_ingreso, a_credito 
    INTO v_id_deposito, v_a_credito
    FROM COMPRAS_CABECERA WHERE id = NEW.id_compra;

    -- STOCK
    CALL sp_actualizar_stock(v_id_deposito, NEW.id_producto, NEW.cantidad, 'SUMAR');

    -- PRODUCTOS
    SELECT cd.id_compra INTO v_ultima_compra
    FROM COMPRAS_DETALLE cd
    INNER JOIN COMPRAS_CABECERA cc ON cd.id_compra = cc.id
    WHERE cd.id_producto = NEW.id_producto AND cc.id_estado <> 4
    ORDER BY cc.fecha_compra DESC, cc.id DESC
    LIMIT 1;

    IF v_ultima_compra = NEW.id_compra THEN
        UPDATE PRODUCTOS 
        SET ultimo_costo_unitario = NEW.costo_unitario 
        WHERE id = NEW.id_producto;
    END IF;

    -- CABECERA (credito o no)
    UPDATE COMPRAS_CABECERA cc
    SET monto_total = monto_total + NEW.subtotal,
        saldo_factura = IF(v_a_credito, saldo_factura + NEW.subtotal, 0.00)
    WHERE cc.id = NEW.id_compra;

    INSERT INTO BITACORA (
    nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
    'COMPRAS_DETALLE', 'INSERT', 2, NOW(),
    JSON_OBJECT('NULL', null),
    JSON_OBJECT('id_detalle',       NEW.id_detalle,
                'id_compra',        NEW.id_compra,
                'id_producto',      NEW.id_producto,
                'cantidad',         NEW.cantidad,
                'costo_unitario',   NEW.costo_unitario,
                'porcentaje_iva',   NEW.porcentaje_iva,
                'subtotal',         NEW.subtotal
                )
  );
END //


/*
    BEFORE UPDATE
    - Mantiene inmutables id_compra e id_producto.
    - Bloquea modificaciones si la factura está ANULADA o es a crédito con pagos aplicados.
    - Verifica stock disponible si se reduce la cantidad.
    - Recalcula IVA y subtotal.
*/
DROP TRIGGER IF EXISTS trg_compras_detalle_before_update //
CREATE TRIGGER trg_compras_detalle_before_update
BEFORE UPDATE ON COMPRAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_id_estado TINYINT UNSIGNED;
    DECLARE v_a_credito BOOLEAN;
    DECLARE v_monto_total DECIMAL(15,2);
    DECLARE v_saldo_factura DECIMAL(15,2);
    DECLARE v_id_deposito INT UNSIGNED;
    DECLARE v_stock_cantidad NUMERIC(12,2);
    DECLARE v_porcentaje_iva NUMERIC(5,2);

    SET NEW.id_compra = OLD.id_compra;
    SET NEW.id_producto = OLD.id_producto;

    SELECT id_estado, a_credito, monto_total, saldo_factura, id_deposito_ingreso
    INTO v_id_estado, v_a_credito, v_monto_total, v_saldo_factura, v_id_deposito
    FROM COMPRAS_CABECERA c WHERE c.id = OLD.id_compra;

    IF v_id_estado = 4 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Los detalles de una compra no pueden ser modificados luego de que sea ANULADA.';
    END IF;

    IF v_a_credito = TRUE AND (v_id_estado = 2 OR v_saldo_factura < v_monto_total) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden modificar detalles de una factura a crédito que ya posee pagos registrados.';
    END IF;

    SET v_stock_cantidad = COALESCE((SELECT cantidad
                                     FROM STOCK_DEPOSITO s 
                                     WHERE s.id_deposito = v_id_deposito AND s.id_producto = OLD.id_producto),
                                    0.00);

    IF NEW.cantidad < OLD.cantidad AND v_stock_cantidad < (OLD.cantidad - NEW.cantidad) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No hay suficiente stock del producto para reducir la cantidad comprada.';
    END IF;

    SELECT porcentaje_iva INTO v_porcentaje_iva FROM PRODUCTOS p WHERE p.id = NEW.id_producto LIMIT 1;
    IF v_porcentaje_iva IS NOT NULL THEN
        SET NEW.porcentaje_iva = v_porcentaje_iva;
    END IF;

    SET NEW.subtotal = NEW.cantidad * NEW.costo_unitario;
END //


/*
    AFTER UPDATE
    - Ajusta el stock por el diferencial exacto en el depósito de ingreso.
    - Actualiza monto_total y saldo_factura por el diferencial.
    - Actualiza ultimo_costo_unitario si cambió el precio y es la compra más reciente.
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_compras_detalle_after_update //
CREATE TRIGGER trg_compras_detalle_after_update
AFTER UPDATE ON COMPRAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_id_deposito TINYINT UNSIGNED;
    DECLARE v_a_credito BOOLEAN;
    DECLARE v_diff_subtotal NUMERIC(15,2);
    DECLARE v_diff_cantidad NUMERIC(12,2);
    DECLARE v_ultima_compra INT UNSIGNED;

    SET v_diff_subtotal = NEW.subtotal - OLD.subtotal;
    SET v_diff_cantidad = NEW.cantidad - OLD.cantidad;

    SELECT id_deposito_ingreso, a_credito 
    INTO v_id_deposito, v_a_credito
    FROM COMPRAS_CABECERA WHERE id = NEW.id_compra;

    -- STOCK
    IF v_diff_cantidad > 0 THEN
        CALL sp_actualizar_stock(v_id_deposito, NEW.id_producto, v_diff_cantidad, 'SUMAR');
    ELSEIF v_diff_cantidad < 0 THEN
        CALL sp_actualizar_stock(v_id_deposito, NEW.id_producto, ABS(v_diff_cantidad), 'RESTAR');
    END IF;
    
    -- CABECERA (credito o no)
    IF v_diff_subtotal <> 0 THEN
        UPDATE COMPRAS_CABECERA cc
        SET monto_total = monto_total + v_diff_subtotal,
            saldo_factura = IF(v_a_credito, saldo_factura + v_diff_subtotal, 0.00)
        WHERE cc.id = NEW.id_compra;
    END IF;

    -- PRODUCTOS
    IF NEW.costo_unitario <> OLD.costo_unitario THEN
        SELECT cd.id_compra INTO v_ultima_compra
        FROM COMPRAS_DETALLE cd
        INNER JOIN COMPRAS_CABECERA cc ON cd.id_compra = cc.id
        WHERE cd.id_producto = NEW.id_producto AND cc.id_estado <> 4
        ORDER BY cc.fecha_compra DESC, cc.id DESC
        LIMIT 1;

        IF v_ultima_compra = NEW.id_compra THEN
            UPDATE PRODUCTOS 
            SET ultimo_costo_unitario = NEW.costo_unitario 
            WHERE id = NEW.id_producto;
        END IF;
    END IF;

    INSERT INTO BITACORA (
    nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
    'COMPRAS_DETALLE', 'UPDATE', 2, NOW(),
    JSON_OBJECT('id_detalle',       OLD.id_detalle,
                'id_compra',        OLD.id_compra,
                'id_producto',      OLD.id_producto,
                'cantidad',         OLD.cantidad,
                'costo_unitario',   OLD.costo_unitario,
                'porcentaje_iva',   OLD.porcentaje_iva,
                'subtotal',         OLD.subtotal
               ),
    JSON_OBJECT('id_detalle',       NEW.id_detalle,
                'id_compra',        NEW.id_compra,
                'id_producto',      NEW.id_producto,
                'cantidad',         NEW.cantidad,
                'costo_unitario',   NEW.costo_unitario,
                'porcentaje_iva',   NEW.porcentaje_iva,
                'subtotal',         NEW.subtotal
               )
  );
END //


/*
    BEFORE DELETE
    - Bloquea eliminaciones si la factura está ANULADA o es a crédito con pagos aplicados.
    - Verifica que el stock disponible cubra la totalidad de OLD.cantidad.
*/
DROP TRIGGER IF EXISTS trg_compras_detalle_before_delete //
CREATE TRIGGER trg_compras_detalle_before_delete
BEFORE DELETE ON COMPRAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_id_estado TINYINT UNSIGNED;
    DECLARE v_a_credito BOOLEAN;
    DECLARE v_monto_total DECIMAL(15,2);
    DECLARE v_saldo_factura DECIMAL(15,2);
    DECLARE v_id_deposito INT UNSIGNED;
    DECLARE v_stock_cantidad NUMERIC(12,2);

    SELECT id_estado, a_credito, monto_total, saldo_factura, id_deposito_ingreso
    INTO v_id_estado, v_a_credito, v_monto_total, v_saldo_factura, v_id_deposito
    FROM COMPRAS_CABECERA c WHERE c.id = OLD.id_compra;
    
    IF v_id_estado = 4 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden eliminar detalles de una factura ANULADA.';
    END IF;

    IF v_a_credito = TRUE AND (v_id_estado = 2 OR v_saldo_factura < v_monto_total) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden eliminar detalles de una factura a crédito que ya posee pagos registrados.';
    END IF;

    SET v_stock_cantidad = COALESCE((SELECT cantidad
                                     FROM STOCK_DEPOSITO s 
                                     WHERE s.id_deposito = v_id_deposito AND s.id_producto = OLD.id_producto),
                                    0.00);

    IF v_stock_cantidad < OLD.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No hay suficiente stock del producto para eliminar este detalle.';
    END IF;
END //


/*
    AFTER DELETE
    - Resta OLD.cantidad del stock del depósito de ingreso.
    - Resta OLD.subtotal de monto_total y saldo_factura en la cabecera (si es a crédito).
    - Recalcula el último costo unitario tomando la compra válida anterior (o 0.00 si no quedan).
    - Registra en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_compras_detalle_after_delete //
CREATE TRIGGER trg_compras_detalle_after_delete
AFTER DELETE ON COMPRAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_id_deposito INT UNSIGNED;
    DECLARE v_a_credito BOOLEAN;
    DECLARE v_nuevo_ultimo_costo NUMERIC(12,2);

    SELECT id_deposito_ingreso, a_credito 
    INTO v_id_deposito, v_a_credito
    FROM COMPRAS_CABECERA c WHERE c.id = OLD.id_compra;

    -- STOCK
    CALL sp_actualizar_stock(v_id_deposito, OLD.id_producto, OLD.cantidad, 'RESTAR');
    
    -- CABECERA (credito o no)
    UPDATE COMPRAS_CABECERA cc
    SET monto_total = monto_total - OLD.subtotal,
        saldo_factura = IF(v_a_credito, saldo_factura - OLD.subtotal, 0.00)
    WHERE cc.id = OLD.id_compra;

    -- PRODUCTOS
    -- costo de compra valida mas reciente que queda para el producto
    SELECT cd.costo_unitario INTO v_nuevo_ultimo_costo
    FROM COMPRAS_DETALLE cd
    INNER JOIN COMPRAS_CABECERA cc ON cd.id_compra = cc.id
    WHERE cd.id_producto = OLD.id_producto AND cc.id_estado <> 4
    ORDER BY cc.fecha_compra DESC, cc.id DESC
    LIMIT 1;

    UPDATE PRODUCTOS 
    SET ultimo_costo_unitario = COALESCE(v_nuevo_ultimo_costo, 0.00)
    WHERE id = OLD.id_producto;

    INSERT INTO BITACORA (
    nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
    'COMPRAS_DETALLE', 'DELETE', 2, NOW(),
    JSON_OBJECT('id_detalle',       OLD.id_detalle,
                'id_compra',        OLD.id_compra,
                'id_producto',      OLD.id_producto,
                'cantidad',         OLD.cantidad,
                'costo_unitario',   OLD.costo_unitario,
                'porcentaje_iva',   OLD.porcentaje_iva,
                'subtotal',         OLD.subtotal
               ),
    JSON_OBJECT('NULL', null)
  );
END //

DELIMITER ;