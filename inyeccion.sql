USE modulo_compras;
-- ============================================================================
-- SCRIPT DE INYECCIÓN DE DATOS DE PRUEBA (MYSQL)
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- 1. MARCAS
-- ----------------------------------------------------------------------------
INSERT INTO `MARCAS` (`id`, `nombre`) VALUES
(1, 'Pirelli'),
(2, 'Michelin'),
(3, 'Bridgestone'),
(4, 'Mann Filter'),
(5, 'Castrol');

-- ----------------------------------------------------------------------------
-- 2. TIPOS_DE_PRODUCTOS
-- ----------------------------------------------------------------------------
INSERT INTO `TIPOS_DE_PRODUCTOS` (`id`, `descripcion`) VALUES
(1, 'Neumáticos'),
(2, 'Filtros de Aceite'),
(3, 'Filtros de Aire'),
(4, 'Aceites Sintéticos'),
(5, 'Baterías');

-- ----------------------------------------------------------------------------
-- 3. PRODUCTOS
-- ----------------------------------------------------------------------------
INSERT INTO `PRODUCTOS` (`id`, `descripcion`, `id_marca`, `id_tipo`, `ultimo_costo_unitario`, `porcentaje_iva`) VALUES
(1, 'Neumático 175/70 R13 Cinturato P1', 1, 1, 460000.00, 10.00),
(2, 'Neumático 205/55 R16 Primacy 4',    2, 1, 850000.00, 10.00),
(3, 'Filtro de Aceite W 712/83',        4, 2,  65000.00, 10.00),
(4, 'Aceite Edge 5W-30 4L',             5, 4, 280000.00, 10.00),
(5, 'Filtro de Aire C 25 004',          4, 3,  75000.00,  5.00),
(6, 'Batería 12V 60Ah Willard', 3, 5, 520000.00, 10.00);

INSERT INTO `PRODUCTOS` (`id`, `descripcion`, `id_marca`, `id_tipo`, `porcentaje_iva`) VALUES (7, 'Bateria prueba', 3, 5, 10);
-- Entrada de prueba para testear la consulta nro 7.

-- ----------------------------------------------------------------------------
-- 4. DEPOSITOS
-- ----------------------------------------------------------------------------
INSERT INTO `DEPOSITOS` (`id`, `nombre`) VALUES
(1, 'Depósito General'),
(2, 'Salón de Ventas');

-- ----------------------------------------------------------------------------
-- 5. STOCK_DEPOSITO
-- ----------------------------------------------------------------------------
INSERT INTO `STOCK_DEPOSITO` (`id_deposito`, `id_producto`, `cantidad`) VALUES
-- Depósito 1 (Depósito General)
(1, 1, 25.00), -- 20 (Compra 1) - 5 (Transf 1) + 10 (Compra 5)
(1, 2,  7.00), -- 10 (Compra 2) - 3 (Transf 2)
(1, 3, 49.00), -- 50 (Compra 3) - 10 (Transf 3) + 9 (Compra 6)
(1, 4,  2.00), -- 0 + 2 (Transf 4 desde Depósito 2)
(1, 5, 25.00), -- 40 (Compra 3) - 15 (Transf 5)
(1, 6, 0.00),  -- Está registrado como producto, pero en algún momento agotó su stock

-- Depósito 2 (Salón de Ventas)
(2, 1,  5.00), -- 0 + 5 (Transf 1 desde Depósito 1)
(2, 2,  3.00), -- 0 + 3 (Transf 2 desde Depósito 1)
(2, 3, 10.00), -- 0 + 10 (Transf 3 desde Depósito 1)
(2, 4, 13.00), -- 15 (Compra 4) - 2 (Transf 4 hacia Depósito 1)
(2, 5, 15.00); -- 0 + 15 (Transf 5 desde Depósito 1)

-- ----------------------------------------------------------------------------
-- 6. PROVEEDORES
-- ----------------------------------------------------------------------------
INSERT INTO `PROVEEDORES` (`id`, `ruc`, `nombre_razon_social`, `direccion`, `telefono`, `correo`, `linea_credito`, `saldo_linea_credito`) VALUES
(1, '80012345-1', 'Pirelli Paraguay S.A.',          'Av. Mcal. López 1234, Asunción',    '021123456', 'ventas@pirelli.com.py',          100000000.00,  89500000.00),
(2, '80023456-2', 'Importadora Michelin S.R.L.',    'Av. España 567, Asunción',          '021234567', 'contacto@michelin.com.py',       150000000.00, 141500000.00), -- cambiado 30 de octubre para que no falle trigger
(3, '80034567-3', 'Filtros y Lubris S.A.',          'Ruta PY01 Km 12, San Lorenzo',      '021345678', 'ventas@filtrosylubris.com.py',    50000000.00,  45000000.00),
(4, '80045678-4', 'Distribuidora Castrol del Este', 'Av. San Blas 890, Ciudad del Este', '061500100', 'comercial@castroldeleste.com.py', 80000000.00,  80000000.00),
(5, '80056789-5', 'Repuestos y Servicios Itapúa',   'Av. Irrazábal 432, Encarnación',    '071200300', 'contacto@rsitapua.com.py',          612000.00,    612000.00), -- cambiado 30 de octubre para que no falle trigger
(6, '80067890-6', 'Stark Tunning S.A.',             'Calle Los Granados, Bella Vista',   '071999800', 'comercial@starktunnig.com.py',           0.00,         0.00);
-- ----------------------------------------------------------------------------
-- 7. ROLES
-- ----------------------------------------------------------------------------
INSERT INTO `ROLES` (`id`, `nombre`, `descripcion`) VALUES
(1, 'Administrador',        'Acceso total al sistema y gestión general.'),
(2, 'Encargado de Compras', 'Gestión de proveedores, compras y facturas.'),
(3, 'Encargado Depósito',   'Manejo de inventario y transferencias.'),
(4, 'Autorizante',          'Autorización de transferencias y pagos.'),
(5, 'Auditor',              'Acceso de solo lectura para fiscalización.');

-- ----------------------------------------------------------------------------
-- 8. USUARIOS
-- ----------------------------------------------------------------------------
INSERT INTO `USUARIOS` (`id`, `cedula`, `nombre`, `correo`, `id_rol`, `activo`) VALUES
(1, 4567890, 'Carlos Benítez',  'carlos.benitez@empresa.com.py',  1, true),
(2, 3456789, 'María González', 'maria.gonzalez@empresa.com.py', 2, true),
(3, 2345678, 'Juan Pérez',     'juan.perez@empresa.com.py',     3, true),
(4, 1234567, 'Ana Martínez',   'ana.martinez@empresa.com.py',   4, true),
(5, 5678901, 'Roberto Gómez',  'roberto.gomez@empresa.com.py',  5, false);

-- ----------------------------------------------------------------------------
-- 9. ESTADOS_DE_FACTURA
-- ----------------------------------------------------------------------------
INSERT INTO `ESTADOS_DE_FACTURA` (`id`, `descripcion`) VALUES
(1, 'PENDIENTE'),
(2, 'PAGADA'),
(3, 'VENCIDA'),
(4, 'ANULADA');

-- ----------------------------------------------------------------------------
-- 10. FORMAS_DE_PAGO
-- ----------------------------------------------------------------------------
INSERT INTO `FORMAS_DE_PAGO` (`id`, `descripcion`) VALUES
(1, 'Efectivo'),
(2, 'Cheque al Día'),
(3, 'Cheque Diferido'),
(4, 'Transferencia Bancaria'),
(5, 'Tarjeta de Débito');

-- ----------------------------------------------------------------------------
-- 11. COMPRAS_CABECERA
-- ----------------------------------------------------------------------------
INSERT INTO `COMPRAS_CABECERA` (`id`, `numero_factura`, `timbrado`, `id_proveedor`, `fecha_compra`, `fecha_vencimiento`, `a_credito`, `id_deposito_ingreso`, `monto_total`, `saldo_factura`, `id_estado`) VALUES
(1, '001-001-0000101', 12345678, 1, '2026-09-01', '2026-10-01', true,  1, 9000000.00, 7000000.00, 1), -- PENDIENTE
(2, '001-001-0000202', 23456789, 2, '2026-09-05', '2026-09-05', false, 1, 8500000.00,         0.00, 2), -- PAGADA
(3, '001-001-0000303', 34567890, 3, '2026-09-10', '2026-09-25', true,  1, 6250000.00, 5000000.00, 3), -- VENCIDA, se supone que estos datos son vistos a fecha de 1 de octubre de 2026
(4, '001-002-0000404', 45678901, 4, '2026-09-15', '2026-09-15', false, 2, 4200000.00,         0.00, 2), -- PAGADA
(5, '001-001-0000505', 13335678, 1, '2026-09-20', '2026-10-20', true,  1, 4600000.00, 3600000.00, 1), -- PENDIENTE
(6, '001-001-0000601', 92345699, 5, '2026-09-25', '2026-10-25', true, 1, 612000.00, 612000.00, 1); -- PENDIENTE
-- ----------------------------------------------------------------------------
-- 12. COMPRAS_DETALLE
-- ----------------------------------------------------------------------------
INSERT INTO `COMPRAS_DETALLE` (`id_detalle`, `id_compra`, `id_producto`, `cantidad`, `costo_unitario`, `porcentaje_iva`, `subtotal`) VALUES
(1, 1, 1, 20.00, 450000.00, 10.00, 9000000.00), -- Compra 1 (Total: 9.000.000)
(2, 2, 2, 10.00, 850000.00, 10.00, 8500000.00), -- Compra 2 (Total: 8.500.000)
(3, 3, 3, 50.00,  65000.00, 10.00, 3250000.00), -- Compra 3 Item 1
(4, 3, 5, 40.00,  75000.00,  5.00, 3000000.00), -- Compra 3 Item 2 (Suma: 6.250.000)
(5, 4, 4, 15.00, 280000.00, 10.00, 4200000.00), -- Compra 4 (Total: 4.200.000)
(6, 5, 1, 10.00, 460000.00, 10.00, 4600000.00), -- Compra 5 (Total: 4.600.000)
(7, 6, 3, 09.00,  68000.00, 10.00,  612000.00); -- Compra 6 (Total: 612.000)

-- ----------------------------------------------------------------------------
-- 13. ORDENES_DE_PAGO
-- ----------------------------------------------------------------------------
INSERT INTO `ORDENES_DE_PAGO` (`id`, `id_proveedor`, `fecha`, `monto_total`) VALUES
(1, 2, '2026-09-05', 8500000.00),
(2, 4, '2026-09-15', 4200000.00);
/*(3, 1, '2026-09-22', 2000000.00),
(4, 3, '2026-09-25', 1250000.00),
(5, 1, '2026-09-28', 1000000.00);*/

-- ----------------------------------------------------------------------------
-- 14. ORDEN_DE_PAGO_FACTURAS
-- ----------------------------------------------------------------------------
INSERT INTO `ORDEN_DE_PAGO_FACTURAS` (`id`, `id_orden_de_pago`, `id_compra`, `monto_pagado`) VALUES
(1, 1, 2, 8500000.00),
(2, 2, 4, 4200000.00),
(3, 3, 1, 2000000.00),
(4, 4, 3, 1250000.00),
(5, 5, 5, 1000000.00);

-- ----------------------------------------------------------------------------
-- 15. ORDEN_DE_PAGO_FORMAS
-- ----------------------------------------------------------------------------
INSERT INTO `ORDEN_DE_PAGO_FORMAS` (`id`, `id_orden_de_pago`, `id_forma_de_pago`, `monto_pagado`, `referencia`) VALUES
(1, 1, 4, 8500000.00, 'Transf. Itaú N° 987654'),
(2, 2, 1, 4200000.00, 'Pago en Efectivo Caja Chica'),
(3, 3, 2, 2000000.00, 'Cheque N° 000123 Banco Continental'),
(4, 4, 3, 1250000.00, 'Cheque Dif. N° 000456 Banco BNF'),
(5, 5, 4, 1000000.00, 'Transf. Sudameris N° 112233');

-- ----------------------------------------------------------------------------
-- 16. TRANSFERENCIAS_CABECERA
-- ----------------------------------------------------------------------------
INSERT INTO `TRANSFERENCIAS_CABECERA` (`id`, `fecha`, `id_deposito_origen`, `id_deposito_destino`, `id_usuario_encargado`, `id_usuario_autorizante`) VALUES
(1, '2026-09-02', 1, 2, 3, 4), -- Posterior a Compra 1 del 01/09
(2, '2026-09-06', 1, 2, 3, 4), -- Posterior a Compra 2 del 05/09
(3, '2026-09-12', 1, 2, 3, 4), -- Posterior a Compra 3 del 10/09
(4, '2026-09-16', 2, 1, 3, 4), -- Transferencia del Depósito 2 al Depósito 1 (Posterior a Compra 4 del 15/09)
(5, '2026-09-21', 1, 2, 3, 4); -- Posterior a Compra 3 (Prod 5) del 10/09 y Compra 5 del 20/09

-- ----------------------------------------------------------------------------
-- 17. TRANSFERENCIAS_DETALLE
-- ----------------------------------------------------------------------------
INSERT INTO `TRANSFERENCIAS_DETALLE` (`id_detalle`, `id_transferencia`, `id_producto`, `cantidad`) VALUES
(1, 1, 1,  5.00),
(2, 2, 2,  3.00),
(3, 3, 3, 10.00),
(4, 4, 4,  2.00),
(5, 5, 5, 15.00);

-- ----------------------------------------------------------------------------
-- 18. BITACORA
-- ----------------------------------------------------------------------------
INSERT INTO `BITACORA` (`id`, `nombre_tabla`, `operacion`, `id_usuario`, `fecha_hora`, `datos_anteriores`, `datos_nuevos`) VALUES
-- 1. Alta completa del producto 1 (antes de cualquier compra/movimiento)
(1, 'PRODUCTOS', 'INSERT', 1, '2026-09-01 08:00:00', NULL, 
  '{"id": 1, "descripcion": "Neumático 175/70 R13 Cinturato P1", "id_marca": 1, "id_tipo": 1, "ultimo_costo_unitario": 450000.00, "porcentaje_iva": 10.00}'),
-- 2. Alta completa del proveedor 1
(2, 'PROVEEDORES', 'INSERT', 2, '2026-09-01 08:30:00', NULL, 
  '{"id": 1, "ruc": "80012345-1", "nombre_razon_social": "Pirelli Paraguay S.A.", "direccion": "Av. Mcal. López 1234, Asunción", "telefono": "021123456", "correo": "ventas@pirelli.com.py", "linea_credito": 100000000.00, "saldo_linea_credito": 100000000.00}'),
-- 3. Inserción de la Compra Cabecera 1
(3, 'COMPRAS_CABECERA', 'INSERT', 2, '2026-09-01 09:15:00', NULL, 
  '{"id": 1, "numero_factura": "001-001-0000101", "timbrado": 12345678, "id_proveedor": 1, "fecha_compra": "2026-09-01", "fecha_vencimiento": "2026-10-01", "a_credito": true, "id_deposito_ingreso": 1, "monto_total": 9000000.00, "saldo_factura": 9000000.00, "id_estado": 1}'),
-- 4. UPDATE en Proveedor por la Compra a Crédito (Descuento de 9.000.000: 100M -> 91M)
(4, 'PROVEEDORES', 'UPDATE', 2, '2026-09-01 09:15:01',
  '{"id": 1, "ruc": "80012345-1", "nombre_razon_social": "Pirelli Paraguay S.A.", "direccion": "Av. Mcal. López 1234, Asunción", "telefono": "021123456", "correo": "ventas@pirelli.com.py", "linea_credito": 100000000.00, "saldo_linea_credito": 100000000.00}',
  '{"id": 1, "ruc": "80012345-1", "nombre_razon_social": "Pirelli Paraguay S.A.", "direccion": "Av. Mcal. López 1234, Asunción", "telefono": "021123456", "correo": "ventas@pirelli.com.py", "linea_credito": 100000000.00, "saldo_linea_credito": 91000000.00}'),
  -- 5. Borrado de un usuario previo (registrando todos sus atributos antes de eliminarlo)
(5, 'USUARIOS', 'DELETE', 1, '2026-09-02 10:00:00', 
  '{"id": 99, "cedula": 9999999, "nombre": "Usuario Temporal", "correo": "temp@empresa.com.py", "id_rol": 3, "activo": false}', NULL),
-- 6. Inserción de la Transferencia Cabecera 1 (después de la compra del 01/09)
(6, 'TRANSFERENCIAS_CABECERA', 'INSERT', 3, '2026-09-02 11:30:00', NULL, 
  '{"id": 1, "fecha": "2026-09-02", "id_deposito_origen": 1, "id_deposito_destino": 2, "id_usuario_encargado": 3, "id_usuario_autorizante": 4}'),
-- 7. Actualización del saldo de factura tras la Orden de Pago N° 3 (22/09/2026)
(7, 'COMPRAS_CABECERA', 'UPDATE', 2, '2026-09-22 11:30:01',
  '{"id": 1, "numero_factura": "001-001-0000101", "timbrado": 12345678, "id_proveedor": 1, "fecha_compra": "2026-09-01", "fecha_vencimiento": "2026-10-01", "a_credito": true, "id_deposito_ingreso": 1, "monto_total": 9000000.00, "saldo_factura": 9000000.00, "id_estado": 1}',
  '{"id": 1, "numero_factura": "001-001-0000101", "timbrado": 12345678, "id_proveedor": 1, "fecha_compra": "2026-09-01", "fecha_vencimiento": "2026-10-01", "a_credito": true, "id_deposito_ingreso": 1, "monto_total": 9000000.00, "saldo_factura": 7000000.00, "id_estado": 1}'),
-- 8. UPDATE en Proveedor por Pago del 22/09/2026 (Liberación de línea de crédito)
(8, 'PROVEEDORES', 'UPDATE', 2, '2026-09-22 11:30:02',
  '{"id": 1, "ruc": "80012345-1", "nombre_razon_social": "Pirelli Paraguay S.A.", "direccion": "Av. Mcal. López 1234, Asunción", "telefono": "021123456", "correo": "ventas@pirelli.com.py", "linea_credito": 100000000.00, "saldo_linea_credito": 100000000.00}',
  '{"id": 1, "ruc": "80012345-1", "nombre_razon_social": "Pirelli Paraguay S.A.", "direccion": "Av. Mcal. López 1234, Asunción", "telefono": "021123456", "correo": "ventas@pirelli.com.py", "linea_credito": 100000000.00, "saldo_linea_credito": 93000000.00}'),
-- 9. Registro de nueva compra
(9, 'COMPRAS_CABECERA', 'INSERT', 2, '2026-09-25 10:00:00', NULL, 
  '{"id": 6, "numero_factura": "001-001-0000601", "timbrado": 12345678, "id_proveedor": 5, "fecha_compra": "2026-09-25", "fecha_vencimiento": "2026-10-25", "a_credito": true, "id_deposito_ingreso": 1, "monto_total": 612000.00, "saldo_factura": 612000.00, "id_estado": 1}'),
-- Registro del consumo de línea de crédito del Proveedor 5
(10, 'PROVEEDORES', 'UPDATE', 2, '2026-09-25 10:00:01',
  '{"id": 5, "ruc": "80055555-5", "nombre_razon_social": "Distribuidora del Este S.A.", "direccion": "Av. Perú 500, Ciudad del Este", "telefono": "061500123", "correo": "ventas@distribuidoradeleste.com.py", "linea_credito": 612000.00, "saldo_linea_credito": 612000.00}',
  '{"id": 5, "ruc": "80055555-5", "nombre_razon_social": "Distribuidora del Este S.A.", "direccion": "Av. Perú 500, Ciudad del Este", "telefono": "061500123", "correo": "ventas@distribuidoradeleste.com.py", "linea_credito": 612000.00, "saldo_linea_credito": 0.00}');

  SET FOREIGN_KEY_CHECKS = 1;