-- ============================================================================
-- PERMISOS DE USUARIO
-- ============================================================================

-- Creación de los usuarios en el motor MySQL
CREATE USER IF NOT EXISTS 'maria_compras'@'localhost' IDENTIFIED BY 'Compras2026*';
CREATE USER IF NOT EXISTS 'juan_deposito'@'localhost' IDENTIFIED BY 'Deposito2026*';


-- PERMISOS PARA USUARIO 1: maria_compras (Módulo Compras y Pagos)
GRANT SELECT, INSERT, UPDATE, DELETE ON modulo_compras.PROVEEDORES            TO 'maria_compras'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON modulo_compras.COMPRAS_CABECERA       TO 'maria_compras'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON modulo_compras.COMPRAS_DETALLE        TO 'maria_compras'@'localhost';

GRANT EXECUTE ON PROCEDURE modulo_compras.sp_abm_proveedor                TO 'maria_compras'@'localhost';
GRANT EXECUTE ON PROCEDURE modulo_compras.sp_abm_compras                  TO 'maria_compras'@'localhost';
GRANT EXECUTE ON PROCEDURE modulo_compras.ProductosNoCompradosEntreFechas TO 'maria_compras'@'localhost';

GRANT SELECT ON modulo_compras.VISTA_FACTURAS_PROVEEDORES_VENCIDAS        TO 'maria_compras'@'localhost';
GRANT SELECT ON modulo_compras.VISTA_PROVEEDORES_LINEA_CREDITO            TO 'maria_compras'@'localhost';




-- PERMISOS PARA USUARIO 2: juan_deposito (Módulo Productos, Stock y Transferencias)
GRANT SELECT, INSERT, UPDATE, DELETE ON modulo_compras.PRODUCTOS               TO 'juan_deposito'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON modulo_compras.DEPOSITOS               TO 'juan_deposito'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON modulo_compras.STOCK_DEPOSITO          TO 'juan_deposito'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON modulo_compras.TRANSFERENCIAS_CABECERA TO 'juan_deposito'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON modulo_compras.TRANSFERENCIAS_DETALLE  TO 'juan_deposito'@'localhost';

GRANT EXECUTE ON PROCEDURE modulo_compras.ProductosNoCompradosEntreFechas TO 'juan_deposito'@'localhost';
GRANT SELECT ON modulo_compras.VISTA_STOCK_PRODUCTOS                      TO 'juan_deposito'@'localhost';

FLUSH PRIVILEGES;

