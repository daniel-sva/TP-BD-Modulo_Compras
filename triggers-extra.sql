USE modulo_compras;
-- ============================================================================
-- SCRIPT DE TRIGGERS PARA REGLAS DE NEGOCIO Y AUDITORÍA
-- ============================================================================
DELIMITER //




-- --------------------------------------------------------------------------------
/* 
  4. MARCAS
*/
-- --------------------------------------------------------------------------------

/*
-- Registro de Bitácora para MARCAS
*/
DROP TRIGGER IF EXISTS trg_bitacora_marcas_update //

CREATE TRIGGER trg_bitacora_marcas_update
AFTER UPDATE ON MARCAS
FOR EACH ROW
BEGIN
    INSERT INTO BITACORA (
        nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
    ) VALUES (
        'MARCAS', 'UPDATE', 1, NOW(),
        JSON_OBJECT('id', OLD.id, 'nombre', OLD.nombre),
        JSON_OBJECT('id', NEW.id, 'nombre', NEW.nombre)
    );
END //


DELIMITER ;