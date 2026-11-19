-- ============================================================================
-- PERMISOS DE USUARIO
-- ============================================================================
/*
-- Creación limpia de usuarios
*/

CREATE USER 'encargado_compras'@'localhost' IDENTIFIED BY 'Compras2026!';
CREATE USER 'encargado_deposito'@'localhost' IDENTIFIED BY 'Deposito2026!';

-- Asignación de Permisos para Encargado de Compras
GRANT SELECT, INSERT, UPDATE ON modulo_compras.COMPRAS_CABECERA TO 'encargado_compras'@'localhost';
GRANT SELECT, INSERT, UPDATE ON modulo_compras.COMPRAS_DETALLE TO 'encargado_compras'@'localhost';
GRANT SELECT, INSERT, UPDATE ON modulo_compras.PROVEEDORES TO 'encargado_compras'@'localhost';

-- Asignación de Permisos para Encargado de Depósito
GRANT SELECT, INSERT, UPDATE, DELETE ON modulo_compras.STOCK_DEPOSITO TO 'encargado_deposito'@'localhost';
GRANT SELECT, INSERT, UPDATE ON modulo_compras.TRANSFERENCIAS_CABECERA TO 'encargado_deposito'@'localhost';
GRANT SELECT, INSERT, UPDATE ON modulo_compras.TRANSFERENCIAS_DETALLE TO 'encargado_deposito'@'localhost';

FLUSH PRIVILEGES;
