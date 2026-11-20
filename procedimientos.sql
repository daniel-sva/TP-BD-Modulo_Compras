USE modulo_compras;
-- ============================================================================
-- SCRIPT DE PROCEDIMIENTOS ALMACENADOS
-- ============================================================================

-- --------------------------------------------------------------------------------
/* 
  1. Para dar alta/baja/modificación de una tabla simple (proveedores, productos,
     etc)
*/
-- --------------------------------------------------------------------------------

DELIMITER //
/*
    PROCEDIMIENTO ABM SIMPLE: PROVEEDORES
    - Gestiona Alta (INSERT), Baja (DELETE) y Modificación (UPDATE) de proveedores.
    - Inicializa automáticamente saldo_linea_credito en el alta y lo recalcula proporcionalmente en modificaciones.
    - Protegido mediante transacción y manejador de excepciones SQL.
*/
DROP PROCEDURE IF EXISTS sp_abm_proveedor //
CREATE PROCEDURE sp_abm_proveedor(
    IN p_operacion VARCHAR(10),      -- INSERT          UPDATE          DELETE
    IN p_id INT UNSIGNED,            -- Nulo/Ignorado   Requerido       Requerido
    IN p_ruc VARCHAR(20),            -- Requerido       Requerido       Nulo/Ignorado
    IN p_nombre VARCHAR(200),        -- Requerido       Requerido       Nulo/Ignorado
    IN p_direccion TEXT,             -- Opcional        Opcional        Nulo/Ignorado
    IN p_telefono VARCHAR(30),       -- Opcional        Opcional        Nulo/Ignorado
    IN p_correo VARCHAR(100),        -- Opcional        Opcional        Nulo/Ignorado
    IN p_linea_credito DECIMAL(15,2) -- Requerido       Requerido       Nulo/Ignorado
)
BEGIN
    DECLARE v_op VARCHAR(10);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_linea_actual DECIMAL(15,2);
    DECLARE v_saldo_actual DECIMAL(15,2);
    DECLARE v_nuevo_saldo DECIMAL(15,2);
    DECLARE v_msg VARCHAR(255);

    SET v_op = UPPER(TRIM(COALESCE(p_operacion, '')));

    IF v_op = 'INSERT' THEN
        IF TRIM(COALESCE(p_ruc, '')) = '' OR TRIM(COALESCE(p_nombre, '')) = '' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: El RUC y el nombre o razón social son obligatorios para registrar un proveedor.';
        END IF;

        SET p_linea_credito = COALESCE(p_linea_credito, 0.00);
        IF p_linea_credito < 0.00 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: La línea de crédito no puede ser negativa.';
        END IF;

        INSERT INTO PROVEEDORES (
            ruc, nombre_razon_social, direccion, telefono, correo, linea_credito, saldo_linea_credito
        ) VALUES (
            TRIM(p_ruc),
            TRIM(p_nombre),
            NULLIF(TRIM(p_direccion), ''),
            NULLIF(TRIM(p_telefono), ''),
            NULLIF(TRIM(p_correo), ''),
            p_linea_credito,
            p_linea_credito
        );

    ELSEIF v_op = 'UPDATE' THEN
        IF p_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Debe especificar el ID del proveedor a modificar.';
        END IF;

        SELECT COUNT(*) INTO v_existe FROM PROVEEDORES WHERE id = p_id;
        IF v_existe = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: El proveedor especificado no existe.';
        END IF;

        IF TRIM(COALESCE(p_ruc, '')) = '' OR TRIM(COALESCE(p_nombre, '')) = '' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: El RUC y el nombre o razón social no pueden quedar vacíos.';
        END IF;

        SELECT linea_credito, saldo_linea_credito
        INTO v_linea_actual, v_saldo_actual
        FROM PROVEEDORES
        WHERE id = p_id;

        SET p_linea_credito = COALESCE(p_linea_credito, v_linea_actual);
        IF p_linea_credito < 0.00 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: La línea de crédito no puede ser negativa.';
        END IF;

        -- ajustar el saldo disponible manteniendo la deuda actual con el provedor
        SET v_nuevo_saldo = v_saldo_actual + (p_linea_credito - v_linea_actual);

        IF v_nuevo_saldo < 0.00 THEN
            SET v_msg = CONCAT('Operación inválida: Reducir la línea de crédito a Gs. ', p_linea_credito, ' dejaría el saldo disponible en negativo.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        UPDATE PROVEEDORES
        SET ruc                 = TRIM(p_ruc),
            nombre_razon_social = TRIM(p_nombre),
            direccion           = NULLIF(TRIM(p_direccion), ''),
            telefono            = NULLIF(TRIM(p_telefono), ''),
            correo              = NULLIF(TRIM(p_correo), ''),
            linea_credito       = p_linea_credito,
            saldo_linea_credito = v_nuevo_saldo
        WHERE id = p_id;

    ELSEIF v_op = 'DELETE' THEN
        IF p_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Debe especificar el ID del proveedor a eliminar.';
        END IF;

        SELECT COUNT(*) INTO v_existe FROM PROVEEDORES WHERE id = p_id;
        IF v_existe = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: El proveedor especificado no existe.';
        END IF;

        -- Se bloquea por el constraint ON DELETE RESTRICT si tiene compras u órdenes de pago asociadas
        DELETE FROM PROVEEDORES WHERE id = p_id;

    ELSE
        SET v_msg = CONCAT('Operación inválida: "', COALESCE(p_operacion, 'NULL'), '". Use INSERT, UPDATE o DELETE.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
END //
DELIMITER ;


-- --------------------------------------------------------------------------------
/* 
  2. Para dar alta/baja/modificación de una tabla cabecera-detalle (facturas,
     compras u ordenes de pago)
*/
-- --------------------------------------------------------------------------------

DELIMITER //
/*
    PROCEDIMIENTO ABM CABECERA-DETALLE: COMPRAS_CABECERA y COMPRAS_DETALLE
    - INSERT: Crea una compra nueva con N detalles (p_id_compra IS NULL) o agrega detalles a una compra existente (p_id_compra IS NOT NULL).
    - UPDATE: Modifica cantidad y/o costo_unitario de los detalles indicados en p_detalles_json para p_id_compra.
    - DELETE: Si p_detalles_json es NULL, realiza borrado lógico (anulación: id_estado = 4) de la cabecera;
              si p_detalles_json contiene productos, elimina físicamente esos detalles.
    - Todas las reglas de cálculo, stock, línea de crédito y auditoría son ejecutadas por los triggers.
*/
DROP PROCEDURE IF EXISTS sp_abm_compras //
CREATE PROCEDURE sp_abm_compras(
    IN p_operacion          VARCHAR(10),   -- INSERT (Nueva)    INSERT (Agreg. Det.)  UPDATE (Det.)     DELETE (Anular / Borrar Det.)
    IN p_id_compra          INT UNSIGNED,  -- Nulo/Ignorado     Requerido             Requerido         Requerido
    IN p_numero_factura     VARCHAR(20),   -- Requerido         Nulo/Ignorado         Nulo/Ignorado     Nulo/Ignorado
    IN p_timbrado           NUMERIC(20),   -- Requerido         Nulo/Ignorado         Nulo/Ignorado     Nulo/Ignorado
    IN p_id_proveedor       INT UNSIGNED,  -- Requerido         Nulo/Ignorado         Nulo/Ignorado     Nulo/Ignorado
    IN p_fecha_compra       DATE,          -- Requerido         Nulo/Ignorado         Nulo/Ignorado     Nulo/Ignorado
    IN p_fecha_vencimiento  DATE,          -- Req. si crédito   Nulo/Ignorado         Nulo/Ignorado     Nulo/Ignorado
    IN p_a_credito          BOOLEAN,       -- Requerido         Nulo/Ignorado         Nulo/Ignorado     Nulo/Ignorado
    IN p_id_deposito        INT UNSIGNED,  -- Requerido         Nulo/Ignorado         Nulo/Ignorado     Nulo/Ignorado
    IN p_detalles_json      JSON           -- Opcional          Requerido             Requerido         Opcional (NULL=Anular)
)
BEGIN
    DECLARE v_op VARCHAR(10);
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_id_compra_objetivo INT UNSIGNED;
    DECLARE v_cant_json INT DEFAULT 0;
    DECLARE v_productos_invalidos INT DEFAULT 0;
    DECLARE v_total_detalles_actual INT DEFAULT 0;
    DECLARE v_msg VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_op = UPPER(TRIM(COALESCE(p_operacion, '')));
    SET v_cant_json = COALESCE(JSON_LENGTH(p_detalles_json), 0);

    START TRANSACTION;

    -- ========================================================================
    -- 1. INSERT (Factura completa nueva o nuevos detalles a existente)
    -- ========================================================================
    IF v_op = 'INSERT' THEN
        IF p_id_compra IS NULL THEN -- alta de nueva cabecera + detalles
            INSERT INTO COMPRAS_CABECERA (
                numero_factura, timbrado, id_proveedor, fecha_compra, fecha_vencimiento,
                a_credito, id_deposito_ingreso
            ) VALUES (
                p_numero_factura, p_timbrado, p_id_proveedor, p_fecha_compra, p_fecha_vencimiento,
                p_a_credito, p_id_deposito
            );

            SET v_id_compra_objetivo = LAST_INSERT_ID();

        ELSE -- agregar nuevos items a una compra ya existente
            IF v_cant_json = 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: Debe proporcionar al menos un producto en p_detalles_json para agregar a la compra.';
            END IF;

            SELECT COUNT(*) INTO v_existe FROM COMPRAS_CABECERA WHERE id = p_id_compra;
            IF v_existe = 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: La compra a la que intenta agregar detalles no existe.';
            END IF;

            SET v_id_compra_objetivo = p_id_compra;
        END IF;

        -- insertar detalles solo si se enviaron productos en el JSON
        IF v_cant_json > 0 THEN
            INSERT INTO COMPRAS_DETALLE (id_compra, id_producto, cantidad, costo_unitario)
            SELECT
                v_id_compra_objetivo,
                jt.id_producto,
                jt.cantidad,
                jt.costo_unitario
            FROM JSON_TABLE(
                p_detalles_json,
                '$[*]' COLUMNS (
                    id_producto    INT UNSIGNED  PATH '$.id_producto',
                    cantidad       DECIMAL(12,2) PATH '$.cantidad',
                    costo_unitario DECIMAL(12,2) PATH '$.costo_unitario'
                )
            ) AS jt;
        END IF;

    -- ========================================================================
    -- 2. UPDATE (Modificación de cantidad/costo en detalles existentes)
    -- ========================================================================
    ELSEIF v_op = 'UPDATE' THEN
        IF p_id_compra IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Debe indicar p_id_compra para modificar sus detalles.';
        END IF;

        SELECT COUNT(*) INTO v_existe FROM COMPRAS_CABECERA WHERE id = p_id_compra;
        IF v_existe = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: La compra especificada no existe.';
        END IF;

        IF v_cant_json = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Debe indicar en p_detalles_json los productos a modificar (cantidad y/o costo_unitario).';
        END IF;

        -- Verificar que todos los productos enviados en el JSON realmente pertenezcan a esa compra
        SELECT COUNT(*) INTO v_productos_invalidos
        FROM JSON_TABLE(
            p_detalles_json,
            '$[*]' COLUMNS (id_producto INT UNSIGNED PATH '$.id_producto')
        ) AS jt
        LEFT JOIN COMPRAS_DETALLE cd
            ON cd.id_compra = p_id_compra AND cd.id_producto = jt.id_producto
        WHERE cd.id_detalle IS NULL;

        IF v_productos_invalidos > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Uno o más productos del JSON no existen en el detalle de esta compra.';
        END IF;

        -- Actualizar cantidad y/o costo _unitario
        -- si no hay dato (null) en el JSON se conserva el valor anterior
        UPDATE COMPRAS_DETALLE cd
        INNER JOIN JSON_TABLE(
            p_detalles_json,
            '$[*]' COLUMNS (
                id_producto    INT UNSIGNED  PATH '$.id_producto',
                cantidad       DECIMAL(12,2) PATH '$.cantidad',
                costo_unitario DECIMAL(12,2) PATH '$.costo_unitario'
            )
        ) AS jt ON cd.id_compra = p_id_compra AND cd.id_producto = jt.id_producto
        SET cd.cantidad       = COALESCE(jt.cantidad, cd.cantidad),
            cd.costo_unitario = COALESCE(jt.costo_unitario, cd.costo_unitario);

    -- ========================================================================
    -- 3. DELETE (Borrado lógico de cabecera o físico de detalles)
    -- ========================================================================
    ELSEIF v_op = 'DELETE' THEN
        IF p_id_compra IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Debe indicar p_id_compra para realizar la baja.';
        END IF;

        SELECT COUNT(*) INTO v_existe FROM COMPRAS_CABECERA WHERE id = p_id_compra;
        IF v_existe = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: La compra especificada no existe.';
        END IF;

        IF v_cant_json = 0 THEN -- borrado lógico de la factura completa, pasa a estado 4 (ANULADA)
            UPDATE COMPRAS_CABECERA
            SET id_estado = 4
            WHERE id = p_id_compra;
            
        ELSE -- Borrado físico de lineas específicas del detalle
            SELECT COUNT(*) INTO v_productos_invalidos
            FROM JSON_TABLE(
                p_detalles_json,
                '$[*]' COLUMNS (id_producto INT UNSIGNED PATH '$.id_producto')
            ) AS jt
            LEFT JOIN COMPRAS_DETALLE cd
                ON cd.id_compra = p_id_compra AND cd.id_producto = jt.id_producto
            WHERE cd.id_detalle IS NULL;

            IF v_productos_invalidos > 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: Uno o más productos a eliminar no existen en el detalle de esta compra.';
            END IF;

            DELETE cd
            FROM COMPRAS_DETALLE cd
            INNER JOIN JSON_TABLE(
                p_detalles_json,
                '$[*]' COLUMNS (id_producto INT UNSIGNED PATH '$.id_producto')
            ) AS jt ON cd.id_compra = p_id_compra AND cd.id_producto = jt.id_producto;
        END IF;

    ELSE
        SET v_msg = CONCAT('Operación inválida: "', COALESCE(p_operacion, 'NULL'), '". Use INSERT, UPDATE o DELETE.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    COMMIT;
END //
DELIMITER ;


-- --------------------------------------------------------------------------------
/* 
  3. Uno de los informes solicitados.
*/
-- --------------------------------------------------------------------------------

-- Se ubica en el archivo consultas.sql, número 7.


-- --------------------------------------------------------------------------------
/* 
  Función / procedimiento para manejo de stock
*/
-- --------------------------------------------------------------------------------

DELIMITER //
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