USE modulo_compras;

-- ============================================================================
-- BLOQUE 1: CARGA DE TABLAS MAESTRAS Y CATÁLOGOS BASE (INSERCIÓN DIRECTA)
-- ============================================================================

-- 1. Roles y Usuarios PRIMERO (necesarios para que los triggers auditen en BITACORA)
INSERT INTO `ROLES` (`id`, `nombre`, `descripcion`) VALUES
(1, 'Administrador',        'Acceso total al sistema y gestión general.'),
(2, 'Encargado de Compras', 'Gestión de proveedores, compras y facturas.'),
(3, 'Encargado Depósito',   'Manejo de inventario y transferencias.'),
(4, 'Autorizante',          'Autorización de transferencias y pagos.'),
(5, 'Auditor',              'Acceso de solo lectura para fiscalización.');

INSERT INTO `USUARIOS` (`id`, `cedula`, `nombre`, `correo`, `id_rol`, `activo`) VALUES
(1, 4567890, 'Carlos Benítez', 'carlos.benitez@empresa.com.py', 1, true),
(2, 3456789, 'María González', 'maria.gonzalez@empresa.com.py', 2, true),
(3, 2345678, 'Juan Pérez',     'juan.perez@empresa.com.py',     3, true),
(4, 1234567, 'Ana Martínez',   'ana.martinez@empresa.com.py',   4, true),
(5, 5678901, 'Roberto Gómez',  'roberto.gomez@empresa.com.py',  5, false);

-- 2. Resto de tablas independientes (catálogos)
INSERT INTO `MARCAS` (`id`, `nombre`) VALUES
(1, 'Pirelli'),
(2, 'Michelin'),
(3, 'Bridgestone'),
(4, 'Mann Filter'),
(5, 'Castrol');

INSERT INTO `TIPOS_DE_PRODUCTOS` (`id`, `descripcion`) VALUES
(1, 'Neumáticos'),
(2, 'Filtros de Aceite'),
(3, 'Filtros de Aire'),
(4, 'Aceites Sintéticos'),
(5, 'Baterías');

INSERT INTO `DEPOSITOS` (`id`, `nombre`) VALUES
(1, 'Depósito General'),
(2, 'Salón de Ventas');

INSERT INTO `ESTADOS_DE_FACTURA` (`id`, `descripcion`) VALUES
(1, 'PENDIENTE'),
(2, 'PAGADA'),
(3, 'VENCIDA'),
(4, 'ANULADA');

INSERT INTO `FORMAS_DE_PAGO` (`id`, `descripcion`) VALUES
(1, 'Efectivo'),
(2, 'Cheque al Día'),
(3, 'Cheque Diferido'),
(4, 'Transferencia Bancaria'),
(5, 'Tarjeta de Débito');

-- 3. Productos (depende de MARCAS, TIPOS_DE_PRODUCTOS y audita en BITACORA)
INSERT INTO `PRODUCTOS` (`id`, `descripcion`, `id_marca`, `id_tipo`, `porcentaje_iva`) VALUES
(1, 'Neumático 175/70 R13 Cinturato P1', 1, 1, 10.00),
(2, 'Neumático 205/55 R16 Primacy 4',    2, 1, 10.00),
(3, 'Filtro de Aceite W 712/83',         4, 2, 10.00),
(4, 'Aceite Edge 5W-30 4L',              5, 4, 10.00),
(5, 'Filtro de Aire C 25 004',           4, 3,  5.00),
(6, 'Batería 12V 60Ah Willard',          3, 5, 10.00),
(7, 'Bateria prueba',                    3, 5, 10.00);


-- ============================================================================
-- BLOQUE 2: STOCK INICIAL DE PRUEBA, ABM PROVEEDORES Y ABM COMPRAS DINÁMICO
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1. Stock inicial para el Producto 7 ('Bateria prueba')
-- (Permite demostrar que existe en depósito pero jamás fue comprado en el SP N° 7)
-- ----------------------------------------------------------------------------
CALL sp_actualizar_stock(1, 7, 10.00, 'SUMAR');


-- ----------------------------------------------------------------------------
-- 2.2. ALTA DE PROVEEDORES MEDIANTE sp_abm_proveedor (IDs 1 al 6 + ID 7 de prueba)
-- ----------------------------------------------------------------------------
CALL sp_abm_proveedor('INSERT', NULL, '80012345-1', 'Pirelli Paraguay S.A.',          'Av. Mcal. López 1234, Asunción',    '021123456', 'ventas@pirelli.com.py',          100000000.00);
CALL sp_abm_proveedor('INSERT', NULL, '80023456-2', 'Importadora Michelin S.R.L.',    'Av. España 567, Asunción',          '021234567', 'contacto@michelin.com.py',       150000000.00);
CALL sp_abm_proveedor('INSERT', NULL, '80034567-3', 'Filtros y Lubris S.A.',          'Ruta PY01 Km 12, San Lorenzo',      '021345678', 'ventas@filtrosylubris.com.py',    50000000.00);
CALL sp_abm_proveedor('INSERT', NULL, '80045678-4', 'Distribuidora Castrol del Este', 'Av. San Blas 890, Ciudad del Este', '061500100', 'comercial@castroldeleste.com.py', 80000000.00);
CALL sp_abm_proveedor('INSERT', NULL, '80056789-5', 'Repuestos y Servicios Itapúa',   'Av. Irrazábal 432, Encarnación',    '071200300', 'contacto@rsitapua.com.py',          612000.00);
CALL sp_abm_proveedor('INSERT', NULL, '80067890-6', 'Stark Tunning S.A.',             'Calle Los Granados, Bella Vista',   '071999800', 'comercial@starktunnig.com.py',           0.00);

-- Proveedor 7: creado específicamente para probar UPDATE y posterior DELETE en vivo
CALL sp_abm_proveedor('INSERT', NULL, '80077788-9', 'AutoPartes Encarnación S.R.L.',  'Av. Caballero 850, Encarnación',    '071204400', 'info@autopartesenc.com.py',       15000000.00);


-- ----------------------------------------------------------------------------
-- 2.3. MODIFICACIÓN DE PROVEEDOR MEDIANTE sp_abm_proveedor
-- (Amplía línea de crédito de 15M a 25M y actualiza teléfono/correo en ID 7)
-- ----------------------------------------------------------------------------
CALL sp_abm_proveedor(
    'UPDATE', 7, '80077788-9', 'AutoPartes Encarnación S.R.L.',
    'Av. Caballero 850, Encarnación', '071209999', 'ventas@autopartesenc.com.py', 25000000.00
);


-- ----------------------------------------------------------------------------
-- 2.4. ALTA DE COMPRAS MEDIANTE sp_abm_compras (Compras 1 a 6)
-- Los triggers calculan subtotales, totales, estados, crédito, stock y último costo.
-- ----------------------------------------------------------------------------

-- Compra 1: Crédito | Pirelli (ID 1) | Depósito 1 | Nace PENDIENTE (venc. 01/12/2026)
CALL sp_abm_compras(
    'INSERT', NULL, '001-001-0000101', 12345678, 1, '2026-11-01', '2026-12-01', TRUE, 1,
    '[{"id_producto": 1, "cantidad": 20.00, "costo_unitario": 450000.00}]'
);

-- Compra 2: Contado | Michelin (ID 2) | Depósito 1 | Nace PAGADA (no consume crédito)
CALL sp_abm_compras(
    'INSERT', NULL, '001-001-0000202', 23456789, 2, '2026-11-04', '2026-11-04', FALSE, 1,
    '[{"id_producto": 2, "cantidad": 10.00, "costo_unitario": 850000.00}]'
);

-- Compra 3: Crédito | Filtros y Lubris (ID 3) | Depósito 1 | Nace VENCIDA (venc. 15/11/2026 < hoy)
CALL sp_abm_compras(
    'INSERT', NULL, '001-001-0000303', 34567890, 3, '2026-11-05', '2026-11-15', TRUE, 1,
    '[{"id_producto": 3, "cantidad": 50.00, "costo_unitario": 65000.00},
      {"id_producto": 5, "cantidad": 40.00, "costo_unitario": 75000.00}]'
);

-- Compra 4: Contado | Castrol (ID 4) | Depósito 2 (Salón) | Nace PAGADA
CALL sp_abm_compras(
    'INSERT', NULL, '001-002-0000404', 45678901, 4, '2026-11-08', '2026-11-08', FALSE, 2,
    '[{"id_producto": 4, "cantidad": 15.00, "costo_unitario": 280000.00}]'
);

-- Compra 5: Crédito | Pirelli (ID 1) | Depósito 1 | Actualiza último costo Prod 1 a 460.000
CALL sp_abm_compras(
    'INSERT', NULL, '001-001-0000505', 13335678, 1, '2026-11-12', '2026-12-12', TRUE, 1,
    '[{"id_producto": 1, "cantidad": 10.00, "costo_unitario": 460000.00}]'
);

-- Compra 6: Crédito | Repuestos Itapúa (ID 5) | Depósito 1 | Copa su línea de crédito (612.000 -> 0)
-- Además hace que Prod 3 tenga compras en más de un proveedor (Prov 3 y Prov 5)
CALL sp_abm_compras(
    'INSERT', NULL, '001-001-0000601', 92345699, 5, '2026-11-16', '2026-12-16', TRUE, 1,
    '[{"id_producto": 3, "cantidad": 9.00, "costo_unitario": 68000.00}]'
);


-- ----------------------------------------------------------------------------
-- 2.5. VARIACIONES DINÁMICAS DE DETALLES Y ANULACIÓN CON sp_abm_compras
-- ----------------------------------------------------------------------------

-- A) Agregar un nuevo detalle (Prod 6) a una factura existente (Compra 4)
CALL sp_abm_compras(
    'INSERT', 4, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    '[{"id_producto": 6, "cantidad": 2.00, "costo_unitario": 520000.00}]'
);

-- B) Editar cantidad (2 -> 3) y costo (520.000 -> 515.000) del Prod 6 en la Compra 4
-- El trigger ajusta el stock por diferencia (+1), recalcula total (5.745.000) y último costo (515.000)
CALL sp_abm_compras(
    'UPDATE', 4, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    '[{"id_producto": 6, "cantidad": 3.00, "costo_unitario": 515000.00}]'
);

-- C) Crear Compra 7 a crédito (Castrol, ID 4) con 2 ítems para luego vaciarla y anularla
CALL sp_abm_compras(
    'INSERT', NULL, '001-002-0000999', 45678901, 4, '2026-11-18', '2026-12-18', TRUE, 1,
    '[{"id_producto": 2, "cantidad": 4.00, "costo_unitario": 850000.00},
      {"id_producto": 6, "cantidad": 2.00, "costo_unitario": 515000.00}]'
);

-- D) Eliminar un detalle puntual (Prod 2) de la Compra 7 (restituye stock y 3.400.000 de crédito)
CALL sp_abm_compras(
    'DELETE', 7, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    '[{"id_producto": 2}]'
);

-- E) Eliminar el último detalle restante (Prod 6) de la Compra 7
-- La factura queda activa con monto_total = 0.00 (no pasa a PAGADA) y restituye los 1.030.000 restantes
CALL sp_abm_compras(
    'DELETE', 7, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    '[{"id_producto": 6}]'
);

-- F) Anular lógicamente la cabecera de la Compra 7 (pasa a id_estado = 4 ANULADA)
CALL sp_abm_compras(
    'DELETE', 7, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL
);


-- ----------------------------------------------------------------------------
-- 2.6. BAJA DE PROVEEDORES MEDIANTE sp_abm_proveedor
-- ----------------------------------------------------------------------------

-- Eliminación exitosa: Proveedor 7 no tiene facturas asociadas
CALL sp_abm_proveedor('DELETE', 7, NULL, NULL, NULL, NULL, NULL, NULL);

-- [PRUEBA DE ERROR] Descomentar:
-- Intentar eliminar Proveedor 1 (tiene compras registradas -> falla por FK RESTRICT)
-- CALL sp_abm_proveedor('DELETE', 1, NULL, NULL, NULL, NULL, NULL, NULL);


-- ----------------------------------------------------------------------------
-- 2.7. VERIFICACIÓN DE ESTADO ACTUAL Y AUDITORÍA AUTOMÁTICA EN BITÁCORA
-- ----------------------------------------------------------------------------
SELECT id, ruc, nombre_razon_social, linea_credito, saldo_linea_credito FROM PROVEEDORES;
SELECT id, numero_factura, id_proveedor, fecha_compra, fecha_vencimiento, a_credito, monto_total, saldo_factura, id_estado FROM COMPRAS_CABECERA;
SELECT * FROM STOCK_DEPOSITO ORDER BY id_deposito, id_producto;
SELECT id, descripcion, ultimo_costo_unitario FROM PRODUCTOS;

-- Consultar los registros generados automáticamente por los triggers en BITACORA
SELECT id, nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
FROM BITACORA
ORDER BY id ASC;


-- ============================================================================
-- BLOQUE 3: TRANSFERENCIAS ENTRE DEPÓSITOS Y ÓRDENES DE PAGO (DINÁMICO)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1. TRANSFERENCIAS ENTRE DEPÓSITOS
-- De los 7 productos con stock actual, trasladamos parcialmente 4 productos
-- (IDs 1, 2, 3 y 4) y dejamos 3 productos sin mover (IDs 5, 6 y 7).
-- ----------------------------------------------------------------------------

-- Transferencia 1: Depósito General (1) -> Salón de Ventas (2) | Prod 1 (5 unid.)
INSERT INTO TRANSFERENCIAS_CABECERA (fecha, id_deposito_origen, id_deposito_destino, id_usuario_encargado, id_usuario_autorizante)
VALUES ('2026-11-03', 1, 2, 3, 4);

INSERT INTO TRANSFERENCIAS_DETALLE (id_transferencia, id_producto, cantidad)
VALUES (1, 1, 5.00);

-- Transferencia 2: Depósito General (1) -> Salón de Ventas (2) | Prod 2 (3 unid.) y Prod 3 (10 unid.)
INSERT INTO TRANSFERENCIAS_CABECERA (fecha, id_deposito_origen, id_deposito_destino, id_usuario_encargado, id_usuario_autorizante)
VALUES ('2026-11-06', 1, 2, 3, 4);

INSERT INTO TRANSFERENCIAS_DETALLE (id_transferencia, id_producto, cantidad) VALUES
(2, 2,  3.00),
(2, 3, 10.00);

-- Transferencia 3: Salón de Ventas (2) -> Depósito General (1) | Prod 4 (2 unid.)
INSERT INTO TRANSFERENCIAS_CABECERA (fecha, id_deposito_origen, id_deposito_destino, id_usuario_encargado, id_usuario_autorizante)
VALUES ('2026-11-10', 2, 1, 3, 4);

INSERT INTO TRANSFERENCIAS_DETALLE (id_transferencia, id_producto, cantidad)
VALUES (3, 4, 2.00);

-- Transferencia 4: Depósito General (1) -> Salón de Ventas (2) | Prod 3 (15 unid.)
-- (Creada para demostrar a continuación su eliminación completa desde la cabecera)
INSERT INTO TRANSFERENCIAS_CABECERA (fecha, id_deposito_origen, id_deposito_destino, id_usuario_encargado, id_usuario_autorizante)
VALUES ('2026-11-18', 1, 2, 3, 4);

INSERT INTO TRANSFERENCIAS_DETALLE (id_transferencia, id_producto, cantidad)
VALUES (4, 3, 15.00);


-- A) UPDATE en detalle de Transferencia 1 (aumenta Prod 1 de 5.00 a 8.00 unidades)
-- El trigger ajusta automáticamente la diferencia (+3): Dep 1 baja a 22.00 y Dep 2 sube a 8.00
UPDATE TRANSFERENCIAS_DETALLE
SET cantidad = 8.00
WHERE id_transferencia = 1 AND id_producto = 1;

-- B) DELETE desde cabecera de Transferencia 4
-- El trigger elimina el detalle asociado y restituye las 15 unidades de Prod 3 al Depósito 1 (49.00)
DELETE FROM TRANSFERENCIAS_CABECERA
WHERE id = 4;

-- Verificar existencias tras las transferencias (Prod 5, 6 y 7 permanecen intactos en su depósito original)
SELECT * FROM STOCK_DEPOSITO ORDER BY id_deposito, id_producto;


-- ----------------------------------------------------------------------------
-- 3.2. ÓRDENES DE PAGO (PAGOS PARCIALES, PAGO TOTAL Y MÚLTIPLES DETALLES)
-- Nota: Solo se pagan facturas a crédito (Compras 1, 3, 5 y 6), ya que las
-- compras al contado (2 y 4) nacen pagadas con saldo 0.00.
-- ----------------------------------------------------------------------------

-- ORDEN DE PAGO 1: Proveedor 1 (Pirelli) - Múltiples facturas (pagos parciales) y múltiples formas de pago
-- Nace en borrador (monto_total = 0.00, confirmado = FALSE)
INSERT INTO ORDENES_DE_PAGO (id_proveedor, fecha)
VALUES (1, '2026-11-15');

-- Detalle de facturas abonadas parcialmente en la OP 1 (Total: 3.000.000)
INSERT INTO ORDEN_DE_PAGO_FACTURAS (id_orden_de_pago, id_compra, monto_pagado) VALUES
(1, 1, 2000000.00), -- Compra 1 (9.000.000 -> saldo quedará en 7.000.000)
(1, 5, 1000000.00); -- Compra 5 (4.600.000 -> saldo quedará en 3.600.000)

-- Detalle de formas de pago de la OP 1 (Cheque + Transferencia = 3.000.000)
INSERT INTO ORDEN_DE_PAGO_FORMAS (id_orden_de_pago, id_forma_de_pago, monto_pagado, referencia) VALUES
(1, 2, 2000000.00, 'Cheque N° 000123 Banco Continental'),
(1, 4, 1000000.00, 'Transf. Sudameris N° 112233');

-- Confirmar OP 1: descuenta saldos de Compras 1 y 5, y libera 3.000.000 en el crédito de Pirelli (86.4M -> 89.4M)
UPDATE ORDENES_DE_PAGO SET confirmado = TRUE WHERE id = 1;


-- ORDEN DE PAGO 2: Proveedor 3 (Filtros y Lubris) - Pago parcial sobre factura VENCIDA (Compra 3)
INSERT INTO ORDENES_DE_PAGO (id_proveedor, fecha)
VALUES (3, '2026-11-18');

INSERT INTO ORDEN_DE_PAGO_FACTURAS (id_orden_de_pago, id_compra, monto_pagado)
VALUES (2, 3, 1250000.00); -- Compra 3 (6.250.000 -> saldo quedará en 5.000.000, sigue VENCIDA)

INSERT INTO ORDEN_DE_PAGO_FORMAS (id_orden_de_pago, id_forma_de_pago, monto_pagado, referencia)
VALUES (2, 3, 1250000.00, 'Cheque Dif. N° 000456 Banco BNF');

-- Confirmar OP 2: libera 1.250.000 en crédito de Proveedor 3 (43.75M -> 45.00M)
UPDATE ORDENES_DE_PAGO SET confirmado = TRUE WHERE id = 2;


-- ORDEN DE PAGO 3: Proveedor 5 (Repuestos Itapúa) - Pago TOTAL de factura pendiente (Compra 6)
INSERT INTO ORDENES_DE_PAGO (id_proveedor, fecha)
VALUES (5, '2026-11-19');

INSERT INTO ORDEN_DE_PAGO_FACTURAS (id_orden_de_pago, id_compra, monto_pagado)
VALUES (3, 6, 612000.00); -- Compra 6 (612.000 -> saldo quedará en 0.00 y pasará a estado 2 PAGADA)

INSERT INTO ORDEN_DE_PAGO_FORMAS (id_orden_de_pago, id_forma_de_pago, monto_pagado, referencia)
VALUES (3, 1, 612000.00, 'Pago en Efectivo Caja Chica');

-- Confirmar OP 3: libera el 100% de la línea de crédito de Proveedor 5 (0.00 -> 612.000.00)
UPDATE ORDENES_DE_PAGO SET confirmado = TRUE WHERE id = 3;


-- ----------------------------------------------------------------------------
-- 3.3. VERIFICACIÓN INTERMEDIA TRAS CONFIRMAR LAS ÓRDENES DE PAGO
-- ----------------------------------------------------------------------------
SELECT id, nombre_razon_social, linea_credito, saldo_linea_credito FROM PROVEEDORES;
SELECT id, numero_factura, id_proveedor, monto_total, saldo_factura, id_estado FROM COMPRAS_CABECERA;
SELECT * FROM ORDENES_DE_PAGO;


-- ----------------------------------------------------------------------------
-- 3.4. REVERSIÓN A BORRADOR Y ELIMINACIÓN DESDE CABECERA DE ÓRDENES DE PAGO
-- ----------------------------------------------------------------------------

-- A) Volver la Orden de Pago 2 (Proveedor 3) a estado borrador (confirmado = FALSE)
-- Restituye el saldo de la Compra 3 (5.000.000 -> 6.250.000) y vuelve a descontar 1.250.000 del crédito (45M -> 43.75M)
UPDATE ORDENES_DE_PAGO
SET confirmado = FALSE
WHERE id = 2;

-- B) Eliminar por completo la Orden de Pago 3 (Proveedor 5) desde la cabecera
-- Por regla del trigger, primero se desconfirma (restituye deuda de 612.000 en Compra 6 y deja crédito en 0.00)
-- y luego se elimina la cabecera (que borra en cascada sus detalles de facturas y formas de pago).
UPDATE ORDENES_DE_PAGO SET confirmado = FALSE WHERE id = 3;
DELETE FROM ORDENES_DE_PAGO WHERE id = 3;

-- [PRUEBA DE ERROR EN VIVO] Intentar borrar una orden confirmada directamente sin pasarla a borrador:
-- DELETE FROM ORDENES_DE_PAGO WHERE id = 1;


-- ----------------------------------------------------------------------------
-- 3.5. VERIFICACIÓN FINAL DE SALDOS, CRÉDITOS Y BITÁCORA
-- ----------------------------------------------------------------------------
SELECT id, nombre_razon_social, linea_credito, saldo_linea_credito FROM PROVEEDORES;
SELECT id, numero_factura, id_proveedor, fecha_compra, fecha_vencimiento, monto_total, saldo_factura, id_estado FROM COMPRAS_CABECERA;
SELECT * FROM ORDENES_DE_PAGO;
SELECT * FROM ORDEN_DE_PAGO_FACTURAS;
SELECT * FROM ORDEN_DE_PAGO_FORMAS;

-- Ver los últimos registros auditados automáticamente en BITACORA
SELECT id, nombre_tabla, operacion, id_usuario, fecha_hora, datos_anteriores, datos_nuevos
FROM BITACORA
ORDER BY id DESC
LIMIT 20;