USE modulo_compras;
-- ============================================================================
-- SCRIPT DE VISTAS (MYSQL)
-- ============================================================================

-- --------------------------------------------------------------------------------
/* 
  1. Facturas de Proveedores Vencidas
*/
-- --------------------------------------------------------------------------------
CREATE OR REPLACE VIEW VISTA_FACTURAS_PROVEEDORES_VENCIDAS ASProductosNoCompradosEntreFechas
SELECT 
    ca.id AS codigo_compra,
    ca.numero_factura AS nro_factura,
    ca.timbrado AS timbrado,
    pr.ruc AS ruc_proveedor,
    pr.nombre_razon_social AS proveedor,
    DATE_FORMAT(ca.fecha_compra, '%d/%m/%Y') AS fecha_emision,
    DATE_FORMAT(ca.fecha_vencimiento, '%d/%m/%Y') AS fecha_vencimiento,
    ca.monto_total AS monto_total,
    ca.saldo_factura AS saldo_pendiente,
    est.descripcion AS estado_factura
FROM COMPRAS_CABECERA ca
INNER JOIN PROVEEDORES pr ON ca.id_proveedor = pr.id
INNER JOIN ESTADOS_DE_FACTURA est ON ca.id_estado = est.id
WHERE ca.id_estado = 3 OR (ca.saldo_factura > 0 AND ca.fecha_vencimiento < '2026-10-01');

-- Ejecutar vista
SELECT * FROM VISTA_FACTURAS_PROVEEDORES_VENCIDAS;

-- --------------------------------------------------------------------------------
/* 
  2. Stocks de productos
*/
-- --------------------------------------------------------------------------------
CREATE OR REPLACE VIEW VISTA_STOCK_PRODUCTOS AS
SELECT 
    p.id AS codigo_producto,
    p.descripcion AS producto,
    m.nombre AS marca,
    tp.descripcion AS tipo_producto,
    COALESCE(d.nombre, 'Sin Asignar') AS deposito,
    COALESCE(s.cantidad, 0.00) AS stock_disponible
FROM PRODUCTOS p
INNER JOIN MARCAS m ON p.id_marca = m.id
INNER JOIN TIPOS_DE_PRODUCTOS tp ON p.id_tipo = tp.id
LEFT JOIN STOCK_DEPOSITO s ON p.id = s.id_producto
LEFT JOIN DEPOSITOS d ON s.id_deposito = d.id
ORDER BY p.id, d.id;

-- Ejecutar vista
SELECT * FROM VISTA_STOCK_PRODUCTOS;

-- --------------------------------------------------------------------------------
/* 
  3. Proveedores con línea de crédito
*/
-- --------------------------------------------------------------------------------
CREATE OR REPLACE VIEW VISTA_PROVEEDORES_LINEA_CREDITO AS
SELECT 
    pr.id AS codigo_proveedor,
    pr.ruc AS ruc,
    pr.nombre_razon_social AS razon_social,
    pr.linea_credito AS linea_credito_asignada,
    (pr.linea_credito - pr.saldo_linea_credito) AS credito_utilizado,
    pr.saldo_linea_credito AS credito_disponible
FROM PROVEEDORES pr
WHERE pr.linea_credito > 0;

-- Ejecutar vista
SELECT * FROM VISTA_PROVEEDORES_LINEA_CREDITO;