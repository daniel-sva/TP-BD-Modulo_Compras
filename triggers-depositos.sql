USE modulo_compras;
DELIMITER //

-- --------------------------------------------------------------------------------
/* 
  INICIO TRIGGERS DEPOSITOS
*/
-- --------------------------------------------------------------------------------

/*
    BEFORE INSERT
    - Normaliza espacios en blanco en el nombre del depósito.
*/
DROP TRIGGER IF EXISTS trg_depositos_before_insert //
CREATE TRIGGER trg_depositos_before_insert
BEFORE INSERT ON DEPOSITOS
FOR EACH ROW
BEGIN
    SET NEW.nombre = NULLIF(TRIM(NEW.nombre), '');
END //


/*
    AFTER INSERT
    - Registro de Bitácora para INSERT.
*/
DROP TRIGGER IF EXISTS trg_depositos_after_insert //
CREATE TRIGGER trg_depositos_after_insert
AFTER INSERT ON DEPOSITOS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'DEPOSITOS', 'INSERT', 3, NOW(),
        JSON_OBJECT('NULL', null),
        JSON_OBJECT('id',     NEW.id,
                    'nombre', NEW.nombre)
    );
END //


/*
    BEFORE UPDATE
    - Normaliza espacios en blanco en el nombre del depósito.
*/
DROP TRIGGER IF EXISTS trg_depositos_before_update //
CREATE TRIGGER trg_depositos_before_update
BEFORE UPDATE ON DEPOSITOS
FOR EACH ROW
BEGIN
    SET NEW.nombre = NULLIF(TRIM(NEW.nombre), '');
END //


/*
    AFTER UPDATE
    - Registro de Bitácora para UPDATE.
*/
DROP TRIGGER IF EXISTS trg_depositos_after_update //
CREATE TRIGGER trg_depositos_after_update
AFTER UPDATE ON DEPOSITOS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'DEPOSITOS', 'UPDATE', 3, NOW(),
        JSON_OBJECT('id',     OLD.id,
                    'nombre', OLD.nombre),
        JSON_OBJECT('id',     NEW.id,
                    'nombre', NEW.nombre)
    );
END //


/*
    AFTER DELETE
    - Registro de Bitácora para DELETE.
*/
DROP TRIGGER IF EXISTS trg_depositos_after_delete //
CREATE TRIGGER trg_depositos_after_delete
AFTER DELETE ON DEPOSITOS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'DEPOSITOS', 'DELETE', 3, NOW(),
        JSON_OBJECT('id',     OLD.id,
                    'nombre', OLD.nombre),
        JSON_OBJECT('NULL', null)
    );
END //


-- --------------------------------------------------------------------------------
/* 
  INICIO TRIGGERS STOCK_DEPOSITO
*/
-- --------------------------------------------------------------------------------

/*
    BEFORE INSERT
    - Control de stock no negativo.
*/
DROP TRIGGER IF EXISTS trg_stock_deposito_before_insert //
CREATE TRIGGER trg_stock_deposito_before_insert
BEFORE INSERT ON STOCK_DEPOSITO
FOR EACH ROW
BEGIN
    IF NEW.cantidad < 0.00 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El stock no puede ser negativo.';
    END IF;
END //


/*
    AFTER INSERT
    - Registro de Bitácora para INSERT.
*/
DROP TRIGGER IF EXISTS trg_stock_deposito_after_insert //
CREATE TRIGGER trg_stock_deposito_after_insert
AFTER INSERT ON STOCK_DEPOSITO
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'STOCK_DEPOSITO', 'INSERT', 3, NOW(),
        JSON_OBJECT('NULL', null),
        JSON_OBJECT('id_deposito', NEW.id_deposito,
                    'id_producto', NEW.id_producto,
                    'cantidad',    NEW.cantidad)
    );
END //


/*
    BEFORE UPDATE
    - Mantiene inmutables id_deposito e id_producto.
    - Control de stock no negativo.
*/
DROP TRIGGER IF EXISTS trg_stock_deposito_before_update //
CREATE TRIGGER trg_stock_deposito_before_update
BEFORE UPDATE ON STOCK_DEPOSITO
FOR EACH ROW
BEGIN
    SET NEW.id_deposito = OLD.id_deposito;
    SET NEW.id_producto = OLD.id_producto;

    IF NEW.cantidad < 0.00 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El stock no puede ser negativo.';
    END IF;
END //

/*
    AFTER UPDATE
    - Registro de Bitácora para UPDATE.
*/
DROP TRIGGER IF EXISTS trg_stock_deposito_after_update //
CREATE TRIGGER trg_stock_deposito_after_update
AFTER UPDATE ON STOCK_DEPOSITO
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'STOCK_DEPOSITO', 'UPDATE', 3, NOW(),
        JSON_OBJECT('id_deposito', OLD.id_deposito,
                    'id_producto', OLD.id_producto,
                    'cantidad',    OLD.cantidad),
        JSON_OBJECT('id_deposito', NEW.id_deposito,
                    'id_producto', NEW.id_producto,
                    'cantidad',    NEW.cantidad)
    );
END //

-- trigger anhadido 18 nov
/*
    BEFORE DELETE
    - Impide eliminar registros de stock que aún tengan mercadería en existencia.
*/
DROP TRIGGER IF EXISTS trg_stock_deposito_before_delete //
CREATE TRIGGER trg_stock_deposito_before_delete
BEFORE DELETE ON STOCK_DEPOSITO
FOR EACH ROW
BEGIN
    IF OLD.cantidad > 0.00 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se puede eliminar un registro de stock con existencia mayor a cero.';
    END IF;
END //


/*
    AFTER DELETE
    - Registro de Bitácora para DELETE en STOCK_DEPOSITO.
*/
DROP TRIGGER IF EXISTS trg_stock_deposito_after_delete //
CREATE TRIGGER trg_stock_deposito_after_delete
AFTER DELETE ON STOCK_DEPOSITO
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'STOCK_DEPOSITO', 'DELETE', 3, NOW(),
        JSON_OBJECT('id_deposito', OLD.id_deposito,
                    'id_producto', OLD.id_producto,
                    'cantidad',    OLD.cantidad),
        JSON_OBJECT('NULL', null)
    );
END //


DELIMITER ;