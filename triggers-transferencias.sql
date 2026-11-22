USE modulo_compras;
DELIMITER //

-- --------------------------------------------------------------------------------
/* 
  INICIO TRIGGERS TRANSFERENCIAS_CABECERA
*/
-- --------------------------------------------------------------------------------

/*
    BEFORE INSERT
    - Valida que el depósito origen y destino sean distintos.
    - Valida que la fecha de transferencia no sea posterior a la fecha actual.
    - Valida que encargado y autorizante sean usuarios distintos, activos y posean los roles correspondientes (3 y 4).
*/
DROP TRIGGER IF EXISTS trg_transferencias_cabecera_before_insert //
CREATE TRIGGER trg_transferencias_cabecera_before_insert
BEFORE INSERT ON TRANSFERENCIAS_CABECERA
FOR EACH ROW
BEGIN
    DECLARE id_rol_encargado INT UNSIGNED;
    DECLARE id_rol_autorizante INT UNSIGNED;
    DECLARE v_activo_encargado BOOLEAN;
    DECLARE v_activo_autorizante BOOLEAN;

    SELECT id_rol, activo
    INTO id_rol_encargado, v_activo_encargado
    FROM USUARIOS
    WHERE id = NEW.id_usuario_encargado;

    SELECT id_rol, activo
    INTO id_rol_autorizante, v_activo_autorizante
    FROM USUARIOS
    WHERE id = NEW.id_usuario_autorizante;

    IF NEW.id_deposito_origen = NEW.id_deposito_destino THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El depósito origen no puede ser igual al destino.';

    ELSEIF NEW.fecha > CURRENT_DATE() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La fecha de transferencia no puede ser posterior a la fecha actual.';

    ELSEIF NEW.id_usuario_encargado = NEW.id_usuario_autorizante THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El encargado y el autorizante de la transferencia deben ser usuarios distintos.';

    ELSEIF v_activo_encargado = FALSE OR v_activo_autorizante = FALSE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Tanto el usuario encargado como el autorizante deben estar activos.';

    ELSEIF id_rol_encargado <> 3 OR id_rol_autorizante <> 4 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El usuario encargado o autorizante no posee el rol adecuado para la transferencia.';
    END IF;
END //


/*
    AFTER INSERT
    - Registro de Bitácora para INSERT.
*/
DROP TRIGGER IF EXISTS trg_transferencias_cabecera_bitacora_insert //
CREATE TRIGGER trg_transferencias_cabecera_bitacora_insert
AFTER INSERT ON TRANSFERENCIAS_CABECERA
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'TRANSFERENCIAS_CABECERA', 'INSERT', 3, NOW(),
        JSON_OBJECT('NULL', null),
        JSON_OBJECT('id',                     NEW.id,
                    'fecha',                  NEW.fecha,
                    'id_deposito_origen',     NEW.id_deposito_origen,
                    'id_deposito_destino',    NEW.id_deposito_destino,
                    'id_usuario_encargado',   NEW.id_usuario_encargado,
                    'id_usuario_autorizante', NEW.id_usuario_autorizante)
    );
END //


/*
    BEFORE UPDATE
    - Impide cambiar depósito origen o destino si la transferencia ya tiene detalles cargados.
    - Valida que depósito origen y destino sean distintos y que la fecha no sea futura.
    - Valida roles (3 y 4), estado activo y distinción entre encargado y autorizante.
*/
DROP TRIGGER IF EXISTS trg_transferencias_cabecera_before_update //
CREATE TRIGGER trg_transferencias_cabecera_before_update
BEFORE UPDATE ON TRANSFERENCIAS_CABECERA
FOR EACH ROW
BEGIN
    DECLARE id_rol_encargado INT UNSIGNED;
    DECLARE id_rol_autorizante INT UNSIGNED;
    DECLARE v_activo_encargado BOOLEAN;
    DECLARE v_activo_autorizante BOOLEAN;
    DECLARE v_tiene_detalles BOOLEAN;

    SELECT id_rol, activo
    INTO id_rol_encargado, v_activo_encargado
    FROM USUARIOS
    WHERE id = NEW.id_usuario_encargado;

    SELECT id_rol, activo
    INTO id_rol_autorizante, v_activo_autorizante
    FROM USUARIOS
    WHERE id = NEW.id_usuario_autorizante;

    SELECT EXISTS (
        SELECT 1 FROM TRANSFERENCIAS_DETALLE WHERE id_transferencia = OLD.id
    ) INTO v_tiene_detalles;

    IF v_tiene_detalles = TRUE AND (NEW.id_deposito_origen <> OLD.id_deposito_origen OR NEW.id_deposito_destino <> OLD.id_deposito_destino) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pueden modificar los depósitos de una transferencia que ya posee productos cargados.';

    ELSEIF NEW.id_deposito_origen = NEW.id_deposito_destino THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El depósito origen no puede ser igual al destino.';

    ELSEIF NEW.fecha > CURRENT_DATE() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La fecha de transferencia no puede ser posterior a la fecha actual.';

    ELSEIF NEW.id_usuario_encargado = NEW.id_usuario_autorizante THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El encargado y el autorizante de la transferencia deben ser usuarios distintos.';

    ELSEIF v_activo_encargado = FALSE OR v_activo_autorizante = FALSE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Tanto el usuario encargado como el autorizante deben estar activos.';

    ELSEIF id_rol_encargado <> 3 OR id_rol_autorizante <> 4 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El usuario encargado o autorizante no posee el rol adecuado.';
    END IF;
END //


/*
    AFTER UPDATE
    - Registro de Bitácora para UPDATE.
*/
DROP TRIGGER IF EXISTS trg_transferencias_cabecera_bitacora_update //
CREATE TRIGGER trg_transferencias_cabecera_bitacora_update
AFTER UPDATE ON TRANSFERENCIAS_CABECERA
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'TRANSFERENCIAS_CABECERA', 'UPDATE', 3, NOW(),
        JSON_OBJECT('id',                     OLD.id,
                    'fecha',                  OLD.fecha,
                    'id_deposito_origen',     OLD.id_deposito_origen,
                    'id_deposito_destino',    OLD.id_deposito_destino,
                    'id_usuario_encargado',   OLD.id_usuario_encargado,
                    'id_usuario_autorizante', OLD.id_usuario_autorizante),
        JSON_OBJECT('id',                     NEW.id,
                    'fecha',                  NEW.fecha,
                    'id_deposito_origen',     NEW.id_deposito_origen,
                    'id_deposito_destino',    NEW.id_deposito_destino,
                    'id_usuario_encargado',   NEW.id_usuario_encargado,
                    'id_usuario_autorizante', NEW.id_usuario_autorizante)
    );
END //


/*
    BEFORE DELETE
    - Elimina primero los detalles asociados para disparar sus triggers para revertir stock y registrar en bitacora.
*/
DROP TRIGGER IF EXISTS trg_transferencias_cabecera_before_delete //
CREATE TRIGGER trg_transferencias_cabecera_before_delete
BEFORE DELETE ON TRANSFERENCIAS_CABECERA
FOR EACH ROW
BEGIN
    DELETE FROM TRANSFERENCIAS_DETALLE WHERE id_transferencia = OLD.id;
END //


/*
    AFTER DELETE
    - Registro de Bitácora para DELETE.
*/
DROP TRIGGER IF EXISTS trg_transferencias_cabecera_bitacora_delete //
CREATE TRIGGER trg_transferencias_cabecera_bitacora_delete
AFTER DELETE ON TRANSFERENCIAS_CABECERA
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'TRANSFERENCIAS_CABECERA', 'DELETE', 3, NOW(),
        JSON_OBJECT('id',                     OLD.id,
                    'fecha',                  OLD.fecha,
                    'id_deposito_origen',     OLD.id_deposito_origen,
                    'id_deposito_destino',    OLD.id_deposito_destino,
                    'id_usuario_encargado',   OLD.id_usuario_encargado,
                    'id_usuario_autorizante', OLD.id_usuario_autorizante),
        JSON_OBJECT('NULL', null)
    );
END //


-- --------------------------------------------------------------------------------
/* 
  INICIO TRIGGERS TRANSFERENCIAS_DETALLE
*/
-- --------------------------------------------------------------------------------

/*
    BEFORE INSERT
    - Verifica que el depósito origen disponga de stock suficiente antes de insertar el detalle.
*/
DROP TRIGGER IF EXISTS trg_transferencias_detalle_before_insert //
CREATE TRIGGER trg_transferencias_detalle_before_insert
BEFORE INSERT ON TRANSFERENCIAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_origen INT UNSIGNED;
    DECLARE v_stock_origen DECIMAL(12,2);

    SELECT id_deposito_origen INTO v_origen
    FROM TRANSFERENCIAS_CABECERA
    WHERE id = NEW.id_transferencia;

    SET v_stock_origen = COALESCE((
        SELECT cantidad FROM STOCK_DEPOSITO
        WHERE id_deposito = v_origen AND id_producto = NEW.id_producto
    ), 0.00);

    IF v_stock_origen < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Stock insuficiente en el depósito origen para realizar la transferencia.';
    END IF;
END //


/*
    AFTER INSERT
    - Resta el stock del depósito origen y lo suma al depósito destino.
    - Registra la operación en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_after_insert_transferencias_detalle //
CREATE TRIGGER trg_after_insert_transferencias_detalle
AFTER INSERT ON TRANSFERENCIAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_origen INT UNSIGNED;
    DECLARE v_destino INT UNSIGNED;

    SELECT id_deposito_origen, id_deposito_destino
    INTO v_origen, v_destino
    FROM TRANSFERENCIAS_CABECERA
    WHERE id = NEW.id_transferencia;

    CALL sp_actualizar_stock(v_origen,  NEW.id_producto, NEW.cantidad, 'RESTAR');
    CALL sp_actualizar_stock(v_destino, NEW.id_producto, NEW.cantidad, 'SUMAR');

    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'TRANSFERENCIAS_DETALLE', 'INSERT', 3, NOW(),
        JSON_OBJECT('NULL', null),
        JSON_OBJECT('id_detalle',       NEW.id_detalle,
                    'id_transferencia', NEW.id_transferencia,
                    'id_producto',      NEW.id_producto,
                    'cantidad',         NEW.cantidad)
    );
END //


/*
    BEFORE UPDATE
    - Mantiene inmutables id_transferencia e id_producto.
    - Valida que exista stock suficiente en origen (si aumenta la cantidad) o en destino (si disminuye).
*/
DROP TRIGGER IF EXISTS trg_transferencias_detalle_before_update //
CREATE TRIGGER trg_transferencias_detalle_before_update
BEFORE UPDATE ON TRANSFERENCIAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_origen INT UNSIGNED;
    DECLARE v_destino INT UNSIGNED;
    DECLARE v_diff DECIMAL(12,2);
    DECLARE v_stock_disponible DECIMAL(12,2);

    SET NEW.id_transferencia = OLD.id_transferencia;
    SET NEW.id_producto      = OLD.id_producto;
    SET v_diff               = NEW.cantidad - OLD.cantidad;

    SELECT id_deposito_origen, id_deposito_destino
    INTO v_origen, v_destino
    FROM TRANSFERENCIAS_CABECERA
    WHERE id = OLD.id_transferencia;

    IF v_diff > 0.00 THEN
        SET v_stock_disponible = COALESCE((
            SELECT cantidad FROM STOCK_DEPOSITO
            WHERE id_deposito = v_origen AND id_producto = OLD.id_producto
        ), 0.00);

        IF v_stock_disponible < v_diff THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Stock insuficiente en el depósito origen para incrementar la transferencia.';
        END IF;
    ELSEIF v_diff < 0.00 THEN
        SET v_stock_disponible = COALESCE((
            SELECT cantidad FROM STOCK_DEPOSITO
            WHERE id_deposito = v_destino AND id_producto = OLD.id_producto
        ), 0.00);

        IF v_stock_disponible < ABS(v_diff) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Stock insuficiente en el depósito destino para reducir la transferencia.';
        END IF;
    END IF;
END //


/*
    AFTER UPDATE
    - Revierte el movimiento anterior (OLD) y aplica el nuevo movimiento (NEW) en ambos depósitos.
    - Registra la operación en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_after_update_transferencias_detalle //
CREATE TRIGGER trg_after_update_transferencias_detalle
AFTER UPDATE ON TRANSFERENCIAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_origen INT UNSIGNED;
    DECLARE v_destino INT UNSIGNED;

    IF OLD.cantidad <> NEW.cantidad THEN -- agregado 19 nov
        SELECT id_deposito_origen, id_deposito_destino
        INTO v_origen, v_destino
        FROM TRANSFERENCIAS_CABECERA
        WHERE id = NEW.id_transferencia;

        CALL sp_actualizar_stock(v_origen, NEW.id_producto, OLD.cantidad, 'SUMAR');
        CALL sp_actualizar_stock(v_origen, NEW.id_producto, NEW.cantidad, 'RESTAR');

        CALL sp_actualizar_stock(v_destino, NEW.id_producto, NEW.cantidad, 'SUMAR');
        CALL sp_actualizar_stock(v_destino, NEW.id_producto, OLD.cantidad, 'RESTAR');
    END IF;

    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'TRANSFERENCIAS_DETALLE', 'UPDATE', 3, NOW(),
        JSON_OBJECT('id_detalle',       OLD.id_detalle,
                    'id_transferencia', OLD.id_transferencia,
                    'id_producto',      OLD.id_producto,
                    'cantidad',         OLD.cantidad),
        JSON_OBJECT('id_detalle',       NEW.id_detalle,
                    'id_transferencia', NEW.id_transferencia,
                    'id_producto',      NEW.id_producto,
                    'cantidad',         NEW.cantidad)
    );
END //


/*
    BEFORE DELETE
    - Verifica que el depósito destino tenga stock suficiente para revertir la transferencia sin quedar en negativo.
*/
DROP TRIGGER IF EXISTS trg_transferencias_detalle_before_delete //
CREATE TRIGGER trg_transferencias_detalle_before_delete
BEFORE DELETE ON TRANSFERENCIAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_destino INT UNSIGNED;
    DECLARE v_stock_destino DECIMAL(12,2);

    SELECT id_deposito_destino INTO v_destino
    FROM TRANSFERENCIAS_CABECERA
    WHERE id = OLD.id_transferencia;

    SET v_stock_destino = COALESCE((
        SELECT cantidad FROM STOCK_DEPOSITO
        WHERE id_deposito = v_destino AND id_producto = OLD.id_producto
    ), 0.00);

    IF v_stock_destino < OLD.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Stock insuficiente en el depósito destino para revertir/eliminar este detalle.';
    END IF;
END //


/*
    AFTER DELETE
    - Devuelve el stock al depósito origen y lo resta del depósito destino.
    - Registra la operación en BITACORA.
*/
DROP TRIGGER IF EXISTS trg_after_delete_transferencias_detalle //
CREATE TRIGGER trg_after_delete_transferencias_detalle
AFTER DELETE ON TRANSFERENCIAS_DETALLE
FOR EACH ROW
BEGIN
    DECLARE v_origen INT UNSIGNED;
    DECLARE v_destino INT UNSIGNED;

    SELECT id_deposito_origen, id_deposito_destino
    INTO v_origen, v_destino
    FROM TRANSFERENCIAS_CABECERA
    WHERE id = OLD.id_transferencia;

    CALL sp_actualizar_stock(v_origen,  OLD.id_producto, OLD.cantidad, 'SUMAR');
    CALL sp_actualizar_stock(v_destino, OLD.id_producto, OLD.cantidad, 'RESTAR');

    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'TRANSFERENCIAS_DETALLE', 'DELETE', 3, NOW(),
        JSON_OBJECT('id_detalle',       OLD.id_detalle,
                    'id_transferencia', OLD.id_transferencia,
                    'id_producto',      OLD.id_producto,
                    'cantidad',         OLD.cantidad),
        JSON_OBJECT('NULL', null)
    );
END //


DELIMITER ;