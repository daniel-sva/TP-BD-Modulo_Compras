USE modulo_compras;
-- ============================================================================
-- SCRIPT DE PROCEDIMIENTOS ALMACENADOS (MYSQL)
-- ============================================================================
DELIMITER //
-- --------------------------------------------------------------------------------
/* 
  1. Para dar alta/baja/modificación de una tabla simple (proveedores, productos,
     etc)
*/
-- --------------------------------------------------------------------------------


-- ABM Proveedores
-- VERIFICAR QUE EL PROVEEDOR NO TENGA FACTURAS A SU NOMBRE ANTES DE ELIMINARLO. CASCADE ENVES DE RESTRICT AL INTENTAR DELETE DE CLAVE
DROP PROCEDURE IF EXISTS sp_abm_proveedor //

CREATE PROCEDURE sp_abm_proveedor(
    IN p_operacion VARCHAR(10),
    IN p_id INT,
    IN p_ruc VARCHAR(20),
    IN p_nombre VARCHAR(200),
    IN p_direccion TEXT,
    IN p_telefono VARCHAR(30),
    IN p_correo VARCHAR(100),
    IN p_linea_credito DECIMAL(15,2)
)
BEGIN
    -- Variables para almacenar los valores actuales antes del UPDATE
    DECLARE v_linea_actual DECIMAL(15,2);
    DECLARE v_saldo_actual DECIMAL(15,2);
    DECLARE v_nuevo_saldo DECIMAL(15,2);
    
    DECLARE v_msg VARCHAR(255);

    IF p_operacion = 'INSERT' THEN
        INSERT INTO PROVEEDORES (
            ruc, nombre_razon_social, direccion, telefono, correo, linea_credito, saldo_linea_credito
        ) VALUES (
            p_ruc, p_nombre, p_direccion, p_telefono, p_correo, p_linea_credito, p_linea_credito
        );

    ELSEIF p_operacion = 'UPDATE' THEN
        -- Obtener los valores actuales del proveedor
        SELECT linea_credito, saldo_linea_credito 
        INTO v_linea_actual, v_saldo_actual
        FROM PROVEEDORES 
        WHERE id = p_id;

        -- Calcular el nuevo saldo basado en la diferencia de la linea
        IF p_linea_credito <> v_linea_actual THEN
            SET v_nuevo_saldo = v_saldo_actual + (p_linea_credito - v_linea_actual);
        ELSE
            SET v_nuevo_saldo = v_saldo_actual;
        END IF;

        -- Validar que el saldo no sea negativo
        IF v_nuevo_saldo < 0 THEN
            SET v_msg = CONCAT('Operacion invalida: La reducción de la línea de crédito a Gs.', p_linea_credito, ' dejaría el saldo en negativo.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        -- Ejecutar la actualizacion segura
        UPDATE PROVEEDORES
        SET ruc = p_ruc,
            nombre_razon_social = p_nombre,
            direccion = p_direccion,
            telefono = p_telefono,
            correo = p_correo,
            saldo_linea_credito = v_nuevo_saldo,
            linea_credito = p_linea_credito
        WHERE id = p_id;

    ELSEIF p_operacion = 'DELETE' THEN
        
        DELETE FROM PROVEEDORES WHERE id = p_id;

    ELSE
        SET v_msg = CONCAT('Operacion invalida: ', p_operacion);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
END //

-- --------------------------------------------------------------------------------
/* 
  2. Para dar alta/baja/modificación de una tabla cabecera-detalle (facturas,
     compras u ordenes de pago)
*/
-- --------------------------------------------------------------------------------

-- ABM Compras

DELIMITER //

DROP PROCEDURE IF EXISTS sp_abm_compras //
CREATE PROCEDURE sp_abm_compras(
    IN p_operacion          VARCHAR(10),   -- 'INSERT', 'UPDATE', 'ANULAR'
    IN p_id_compra          INT,           --  para UPDATE y ANULAR
    IN p_id_usuario         INT,
    IN p_numero_factura     VARCHAR(20),
    IN p_timbrado           NUMERIC(20),
    IN p_id_proveedor       INT,
    IN p_fecha_compra       DATE,
    IN p_fecha_vencimiento  DATE,
    IN p_a_credito          BOOLEAN,
    IN p_id_deposito        INT,
    -- Datos del detalle 
    IN p_id_producto        INT,
    IN p_cantidad           NUMERIC(12,2),
    IN p_costo_unitario     NUMERIC(12,2),
    IN p_porcentaje_iva     NUMERIC(5,2)
)
BEGIN
    -- Declaracion variables de control
    DECLARE v_monto_total      DECIMAL(15,2);
    DECLARE v_saldo_factura    DECIMAL(15,2);
    DECLARE v_id_estado        INT;
    DECLARE v_saldo_disponible DECIMAL(15,2);
    DECLARE v_stock_actual     NUMERIC(12,2);
    DECLARE v_id_compra_nuevo  INT;
    
    -- Si falla ejecuta ROLLBACK solo
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    /*------------------------------------------------------------------
    -- 1. Si es INSERT
    ------------------------------------------------------------------*/
    IF p_operacion = 'INSERT' THEN
        
        -- 1. Validar si es a credito y si fecha_vencimiento >= fecha_compra
        IF p_a_credito = TRUE AND p_fecha_vencimiento < p_fecha_compra THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: La fecha de vencimiento no puede ser menor a la fecha de compra.';
        END IF;

        -- monto total del detalle
        SET v_monto_total = p_cantidad * p_costo_unitario;

        -- 2. Validar que la compra no exceda la linea_credito del proveedor
        IF p_a_credito = TRUE THEN
            SELECT saldo_linea_credito INTO v_saldo_disponible 
            FROM PROVEEDORES WHERE id = p_id_proveedor;
            
            IF v_monto_total > v_saldo_disponible THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: El monto supera la línea de crédito disponible del proveedor.';
            END IF;
            SET v_id_estado = 1; -- PENDIENTE
            SET v_saldo_factura = v_monto_total;
        ELSE
            SET v_id_estado = 2; -- PAGADA
            SET v_saldo_factura = 0.00;
        END IF;

        -- 3. Insertar COMPRAS_CABECERA
        INSERT INTO COMPRAS_CABECERA (
            numero_factura, timbrado, id_proveedor, fecha_compra, fecha_vencimiento, 
            a_credito, id_deposito_ingreso, monto_total, saldo_factura, id_estado
        ) VALUES (
            p_numero_factura, p_timbrado, p_id_proveedor, p_fecha_compra, p_fecha_vencimiento,
            p_a_credito, p_id_deposito, v_monto_total, v_saldo_factura, v_id_estado
        );

        SET v_id_compra_nuevo = LAST_INSERT_ID();

        -- 4. Insertar COMPRAS_DETALLE y incrementar STOCK_DEPOSITO
        INSERT INTO COMPRAS_DETALLE (
            id_compra, id_producto, cantidad, costo_unitario, porcentaje_iva, subtotal
        ) VALUES (
            v_id_compra_nuevo, p_id_producto, p_cantidad, p_costo_unitario, p_porcentaje_iva, v_monto_total
        );

        -- Incrementar stock en el deposito de ingreso usando la funcion auxiliar
        CALL sp_actualizar_stock(p_id_deposito, p_id_producto, p_cantidad, 'SUMAR');

        -- 5 y 6. Si es a credito, descontar de PROVEEDORES.saldo_linea_credito
        IF p_a_credito = TRUE THEN
            UPDATE PROVEEDORES 
            SET saldo_linea_credito = saldo_linea_credito - v_monto_total
            WHERE id = p_id_proveedor;
        END IF;

        -- 7. Registrar auditoria en BITACORA !!
        INSERT INTO BITACORA (nombre_tabla, operacion, id_usuario, fecha_hora, datos_nuevos)
        VALUES ('COMPRAS_CABECERA', 'INSERT', p_id_usuario, NOW(), 
                CONCAT('{"id": ', v_id_compra_nuevo, ', "monto": ', v_monto_total, '}'));


   /* ------------------------------------------------------------------
    -- 2. Si es ANULAR
    ------------------------------------------------------------------*/
    ELSEIF p_operacion = 'ANULAR' THEN
        
        -- 1. Validar que la compra exista y que no esté ya anulada
        SELECT saldo_factura, monto_total, id_proveedor, a_credito, id_deposito_ingreso, id_estado
        INTO v_saldo_factura, v_monto_total, p_id_proveedor, p_a_credito, p_id_deposito, v_id_estado
        FROM COMPRAS_CABECERA WHERE id = p_id_compra;

        IF v_id_estado IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: La compra especificada no existe.';
        END IF;
        IF v_id_estado = 4 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: La compra ya se encuentra anulada.';
        END IF;

        -- 2. Validar que saldo_factura == monto_total (sin pagos aplicados)
        IF p_a_credito = TRUE AND v_saldo_factura < v_monto_total THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No se puede anular porque ya registra pagos.';
        END IF;

        -- Obtener producto y cantidad para validar y revertir stock
        SELECT id_producto, cantidad INTO p_id_producto, v_stock_actual
        FROM COMPRAS_DETALLE WHERE id_compra = p_id_compra LIMIT 1;

        -- 3 y 4. Restar las cantidades compradas del STOCK_DEPOSITO (validando stock suficiente)
        CALL sp_actualizar_stock(p_id_deposito, p_id_producto, v_stock_actual, 'RESTAR');

        -- 5. Si fue a crédito devolver el monto a PROVEEDORES.saldo_linea_credito
        IF p_a_credito = TRUE THEN
            UPDATE PROVEEDORES 
            SET saldo_linea_credito = saldo_linea_credito + v_monto_total
            WHERE id = p_id_proveedor;
        END IF;

        -- 6. Cambiar id_estado = 4 (ANULADA) y saldo_factura = 0
        UPDATE COMPRAS_CABECERA
        SET id_estado = 4, saldo_factura = 0.00
        WHERE id = p_id_compra;

        -- 7. Registrar auditoria en bitacora
        INSERT INTO BITACORA (nombre_tabla, operacion, id_usuario, fecha_hora, datos_nuevos)
        VALUES ('COMPRAS_CABECERA', 'ANULAR', p_id_usuario, NOW(), 
                CONCAT('{"id": ', p_id_compra, ', "estado: "ANULADA"}'));


   /* ------------------------------------------------------------------
    -- 3. Si es UPDATE
    ------------------------------------------------------------------*/
    ELSEIF p_operacion = 'UPDATE' THEN
        
        -- 1. Validar que no tenga pagos aplicados (saldo_factura == monto_total)
        SELECT saldo_factura, monto_total, a_credito INTO v_saldo_factura, v_monto_total, p_a_credito
        FROM COMPRAS_CABECERA WHERE id = p_id_compra;

        IF p_a_credito = TRUE AND v_saldo_factura < v_monto_total THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: No se puede modificar una compra con pagos parciales aplicados.';
        END IF;

        -- 2 y 3. Actualizar datos permitidos de la cabecera
        UPDATE COMPRAS_CABECERA
        SET numero_factura = p_numero_factura,
            timbrado = p_timbrado,
            fecha_vencimiento = p_fecha_vencimiento
        WHERE id = p_id_compra;

        -- 5. Registrar auditoría en bitacora
        INSERT INTO BITACORA (nombre_tabla, operacion, id_usuario, fecha_hora, datos_nuevos)
        VALUES ('COMPRAS_CABECERA', 'UPDATE', p_id_usuario, NOW(), 
                CONCAT('{"id": ', p_id_compra, ', "accion": "MODIFICACION"}'));

    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Operación no válida.';
    END IF;

    COMMIT;
END //

/*
INICIO TRANSACCIÓN (START TRANSACTION)
 │
 ├── SI p_operacion = 'INSERT':
 │     1. Validar si es a crédito y si la fecha_vencimiento >= fecha_compra.
 │     2. Validar que la compra no exceda la linea_credito del proveedor.
 │     3. Insertar COMPRAS_CABECERA (con id_estado = 1 'PENDIENTE' o 2 'PAGADA').
 │     4. Iterar sobre p_detalles_json:
 │          - Insertar COMPRAS_DETALLE.
 │          - Incrementar STOCK_DEPOSITO en id_deposito_ingreso.
 │     5. Actualizar monto_total y saldo_factura en COMPRAS_CABECERA.
 │     6. Si es a crédito, descontar de PROVEEDORES.saldo_linea_credito.
 │     7. Registrar auditoría en BITACORA.
 │
 ├── SI p_operacion = 'ANULAR':
 │     1. Validar que la compra exista y no esté ya 'ANULADA'.
 │     2. Validar que saldo_factura == monto_total (sin pagos aplicados).
 │     3. Validar que haya stock suficiente en id_deposito_ingreso para revertir.
 │     4. Restar las cantidades compradas del STOCK_DEPOSITO.
 │     5. Si fue a crédito, devolver el monto a PROVEEDORES.saldo_linea_credito.
 │     6. Cambiar id_estado = 4 ('ANULADA') y saldo_factura = 0.00.
 │     7. Registrar auditoría en BITACORA.
 │
 └── SI p_operacion = 'UPDATE':
       1. Validar que no tenga pagos aplicados (saldo_factura == monto_total).
       2. Revertir el stock y saldo de línea anteriores (como un rollback temporal).
       3. Reemplazar los registros en COMPRAS_DETALLE con el nuevo JSON.
       4. Aplicar el nuevo stock, recalcular monto_total y ajustar saldo_linea_credito.
       5. Registrar auditoría en BITACORA.

SI OCURRE UN ERROR -> ROLLBACK
SI TODO ES CORRECTO -> COMMIT
*/

-- --------------------------------------------------------------------------------
/* 
  3. Uno de los informes solicitados.
*/
-- --------------------------------------------------------------------------------


-- ============================================================================
-- SCRIPT DE PROCEDIMIENTOS ALMACENADOS AUXILIARES (MYSQL)
-- ============================================================================

-- --------------------------------------------------------------------------------
/* 
  1. Procedimientos almacenados adicionales (ABM)
*/
-- --------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_orden_pago //

CREATE PROCEDURE sp_registrar_orden_pago(
    IN p_id_proveedor INT,
    IN p_fecha DATE,
    IN p_monto_total DECIMAL(15,2),
    OUT p_id_orden INT
)
BEGIN
    INSERT INTO ORDENES_DE_PAGO (id_proveedor, fecha, monto_total)
    VALUES (p_id_proveedor, p_fecha, p_monto_total);
    
    SET p_id_orden = LAST_INSERT_ID();
END //

DROP PROCEDURE IF EXISTS sp_registrar_orden_pago_factura //

CREATE PROCEDURE sp_registrar_orden_pago_factura(
    IN p_id_orden_de_pago INT,
    IN p_id_compra INT,
    IN p_monto_pagado DECIMAL(15,2)
)
BEGIN
    DECLARE v_id_proveedor INT;

    INSERT INTO ORDEN_DE_PAGO_FACTURAS (id_orden_de_pago, id_compra, monto_pagado)
    VALUES (p_id_orden_de_pago, p_id_compra, p_monto_pagado);
    
    UPDATE COMPRAS_CABECERA
    SET saldo_factura = saldo_factura - p_monto_pagado
    WHERE id = p_id_compra;
    
    UPDATE COMPRAS_CABECERA
    SET id_estado = 2 -- PAGADA
    WHERE id = p_id_compra AND saldo_factura <= 0;
    
    SELECT id_proveedor INTO v_id_proveedor FROM ORDENES_DE_PAGO WHERE id = p_id_orden_de_pago;
    
    UPDATE PROVEEDORES
    SET saldo_linea_credito = saldo_linea_credito + p_monto_pagado
    WHERE id = v_id_proveedor;
END //


-- --------------------------------------------------------------------------------
/* 
  2. Funciones / procedimientos para manejo de stock
*/
-- --------------------------------------------------------------------------------

DROP PROCEDURE IF EXISTS sp_actualizar_stock //
CREATE PROCEDURE sp_actualizar_stock(
    IN p_id_deposito INT UNSIGNED,
    IN p_id_producto INT UNSIGNED,
    IN p_cantidad DECIMAL(12,2),
    IN p_operacion VARCHAR(10) -- ****** 'SUMAR' o 'RESTAR'**************
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE stock DECIMAL(12,2) DEFAULT 0.00; -- modif 19 nov (int a decimal)

    IF p_cantidad IS NULL OR p_cantidad < 0.00 THEN -- agregado 19 nov
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La cantidad para actualizar el stock no puede ser negativa ni nula.';
    END IF;

    IF p_operacion IS NULL OR p_operacion NOT IN ('SUMAR', 'RESTAR') THEN -- agregado 19 nov
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Operación de stock no válida (use SUMAR o RESTAR).';
    END IF;

    IF p_cantidad > 0.00 THEN -- agregado 19 nov
        SELECT COUNT(*), COALESCE(MAX(cantidad), 0.00) -- modif 19 nov (anterior: SELECT COUNT(*), cantidad)
        INTO v_existe, stock 
        FROM STOCK_DEPOSITO 
        WHERE id_deposito = p_id_deposito AND id_producto = p_id_producto;

        IF v_existe = 0 THEN
            IF p_operacion = 'SUMAR' THEN
                INSERT INTO STOCK_DEPOSITO (id_deposito, id_producto, cantidad)
                VALUES (p_id_deposito, p_id_producto, p_cantidad);
            ELSE
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: No existe registro de stock en este depósito para restar.';
            END IF;
        ELSE 
            IF p_operacion = 'SUMAR' THEN
                UPDATE STOCK_DEPOSITO 
                SET cantidad = cantidad + p_cantidad
                WHERE id_deposito = p_id_deposito AND id_producto = p_id_producto;
            ELSEIF p_operacion = 'RESTAR' THEN
                IF p_cantidad <= stock THEN -- if modificado 19 nov
                    UPDATE STOCK_DEPOSITO 
                    SET cantidad = cantidad - p_cantidad
                    WHERE id_deposito = p_id_deposito AND id_producto = p_id_producto;
                ELSE
                    SIGNAL SQLSTATE '45000' -- agregado 19 nov
                    SET MESSAGE_TEXT = 'Error: Stock insuficiente en el depósito para realizar la operación.';
                END IF;
            END IF;
        END IF;
    END IF;
END //


DELIMITER ;