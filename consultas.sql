USE modulo_compras;
-- ============================================================================
-- SCRIPT DE CONSULTAS (MYSQL)
-- ============================================================================

-- --------------------------------------------------------------------------------
/* 
  1. Monto del importe total de compras realizadas en un rango de fechas (entre dos
     fechas), desplegar los atributos: fecha, código y nombre de depósito, importe 
     total de compras para esa fecha y depósito.
*/
-- --------------------------------------------------------------------------------
SELECT
  DATE_FORMAT(c.fecha_compra, '%d/%m/%Y') AS fecha,
  d.id AS codigo_deposito,
  d.nombre AS nombre_deposito,
  SUM(c.monto_total) AS importe_total_compras
FROM COMPRAS_CABECERA c
INNER JOIN DEPOSITOS d ON c.id_deposito_ingreso = d.id
WHERE c.fecha_compra BETWEEN '2026-09-05' AND '2026-09-15'
  AND c.id_estado <> 4
GROUP BY c.fecha_compra, d.id, d.nombre
ORDER BY c.fecha_compra ASC;

-- --------------------------------------------------------------------------------
/* 
  2. Productos comprados a proveedores, el criterio de recuperación es por rango de
     proveedores y rango de fechas, desplegar los siguientes atributos: Código y
     nombre del Proveedor, código y descripción del producto, última fecha de
     compra, ultimo costo unitario.
*/
-- --------------------------------------------------------------------------------
SELECT
  pr.id AS codigo_proveedor, pr.nombre_razon_social AS nombre_proveedor, p.id AS codigo_producto,
  p.descripcion AS descripcion_producto, DATE_FORMAT(MAX(c.fecha_compra), '%d/%m/%Y') AS ultima_fecha_compra, p.ultimo_costo_unitario
FROM
  COMPRAS_CABECERA c
  INNER JOIN COMPRAS_DETALLE cd ON c.id = cd.id_compra
  INNER JOIN PRODUCTOS p ON cd.id_producto = p.id
  INNER JOIN PROVEEDORES pr ON c.id_proveedor = pr.id
WHERE
  pr.id BETWEEN 1 AND 5
  AND
  c.fecha_compra BETWEEN '2026-09-01' AND '2026-09-30'
  AND c.id_estado <> 4
GROUP BY pr.id, pr.nombre_razon_social, p.id, p.descripcion, p.ultimo_costo_unitario
ORDER BY pr.id, p.id;

-- --------------------------------------------------------------------------------
/* 
  3. Productos comprados a más de un proveedor por rango de proveedores, desplegar
     los atributos: Código y descripción del Producto, código y nombre del
     proveedor.
*/
-- --------------------------------------------------------------------------------
SELECT
  p.id AS codigo_producto, p.descripcion AS descripcion_producto, pr.id AS codigo_proveedor, pr.nombre_razon_social AS nombre_proveedor
FROM
  PRODUCTOS p
  INNER JOIN COMPRAS_DETALLE cd ON p.id = cd.id_producto
  INNER JOIN COMPRAS_CABECERA c ON cd.id_compra = c.id
  INNER JOIN PROVEEDORES pr ON c.id_proveedor = pr.id
WHERE
  p.id IN (
    SELECT cd_sub.id_producto
      FROM
        COMPRAS_DETALLE cd_sub
        INNER JOIN COMPRAS_CABECERA c_sub ON cd_sub.id_compra = c_sub.id
      WHERE c_sub.id_proveedor BETWEEN 1 AND 5
        AND c_sub.id_estado <> 4
      GROUP BY cd_sub.id_producto
      HAVING COUNT(DISTINCT c_sub.id_proveedor) > 1
  )
  AND pr.id BETWEEN 1 AND 5
  AND c.id_estado <> 4
GROUP BY p.id, p.descripcion, pr.id, pr.nombre_razon_social;

-- --------------------------------------------------------------------------------
/* 
  4. Informe de facturas de compra pendientes de pago, desplegar los atributos: 
  Factura, fecha, código y nombre del proveedor, total de la factura y saldo de la
  factura.
*/
-- --------------------------------------------------------------------------------
SELECT
  c.numero_factura AS Factura, DATE_FORMAT(c.fecha_compra, '%d/%m/%Y') AS Fecha, p.id AS 'Codigo Proveedor',
  p.nombre_razon_social AS 'Nombre Proveedor', c.monto_total AS 'Total Factura',
  c.saldo_factura AS 'Saldo Factura'
FROM
  COMPRAS_CABECERA c
  INNER JOIN PROVEEDORES p ON c.id_proveedor = p.id
WHERE c.saldo_factura > 0 OR c.id_estado = 1
ORDER BY c.fecha_compra ASC;

-- --------------------------------------------------------------------------------
/* 
  5. Ranking de productos (Productos más comprados, por cantidad de productos).
*/
-- --------------------------------------------------------------------------------
SELECT
  p.id AS codigo_producto,
  p.descripcion AS descripcion_producto,
  SUM(cd.cantidad) AS cantidad_total_comprada
FROM
  COMPRAS_DETALLE cd
  INNER JOIN PRODUCTOS p ON cd.id_producto = p.id
  INNER JOIN COMPRAS_CABECERA c ON cd.id_compra = c.id
WHERE c.id_estado <> 4
GROUP BY p.id, p.descripcion
ORDER BY cantidad_total_comprada DESC;

-- --------------------------------------------------------------------------------
/* 
  6. Ranking de proveedores (Proveedores a los que más se les compra, por monto de
     facturación).
*/
-- --------------------------------------------------------------------------------
SELECT
  pr.id AS codigo_proveedor,
  pr.nombre_razon_social AS nombre_proveedor,
  SUM(c.monto_total) AS total_facturado
FROM 
  COMPRAS_CABECERA C
  INNER JOIN PROVEEDORES pr ON c.id_proveedor = pr.id
WHERE c.id_estado <> 4
GROUP BY pr.id, pr.nombre_razon_social
ORDER BY total_facturado DESC;

-- --------------------------------------------------------------------------------
/* 
  7. Productos que no se compraron por rango de fecha, desplegar los atributos: 
     código y descripción del producto, precio de compra, ultima fecha de compra.
     (Resolver con procedimiento almacenado)
*/
-- --------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS ProductosNoCompradosEntreFechas;
DELIMITER //
CREATE PROCEDURE ProductosNoCompradosEntreFechas(
  IN fecha_inicial DATE,
  IN fecha_final DATE
)
BEGIN
  IF fecha_inicial IS NULL OR fecha_final IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Debe especificar tanto la fecha inicial como la fecha final.';
    END IF;

    IF fecha_inicial > fecha_final THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La fecha inicial no puede ser posterior a la fecha final.';
    END IF;

    SELECT
      p.id AS codigo_producto,
      p.descripcion AS descripcion_producto,
      -- Recupera el costo unitario de la ultima compra registrada
      p.ultimo_costo_unitario AS precio_ultima_compra,
      -- Recupera la fecha de la ultima compra registrada ('Sin Compras' si jamas se compro)
      COALESCE(
        (
          SELECT DATE_FORMAT(MAX(c.fecha_compra), '%d/%m/%Y')
          FROM COMPRAS_DETALLE cd
          INNER JOIN COMPRAS_CABECERA c ON c.id = cd.id_compra
          WHERE cd.id_producto = p.id AND c.id_estado <> 4
        ),
        'Sin Compras'
       ) AS ultima_fecha_compra
    FROM PRODUCTOS p
    WHERE NOT EXISTS (
      SELECT 1
      FROM COMPRAS_DETALLE cd
      INNER JOIN COMPRAS_CABECERA c ON c.id = cd.id_compra
      WHERE cd.id_producto = p.id
        AND c.id_estado <> 4 
        AND c.fecha_compra BETWEEN fecha_inicial AND fecha_final
    );
END //
DELIMITER ;

CALL ProductosNoCompradosEntreFechas('2026-09-10', '2026-09-16');

/*
DELIMITER //
-- ABM para consulta de productos no comprados entre fechas
DROP PROCEDURE IF EXISTS productos_no_comprados_entre_fechas //

CREATE PROCEDURE productos_no_comprados_entre_fechas(
  IN fecha1 DATE,
  IN fecha2 DATE
)
BEGIN
  SELECT p.id, p.descripcion,p.ultimo_precio_unitario, MAX(cc.fecha)
  FROM PRODUCTOS p LEFT JOIN COMPRAS_DETALLE cd 
  ON p.id=cd.id_producto LEFT JOIN COMPRAS_CABECERA cc 
  ON cd.id_compra=cc.id
  GROUP BY p.id
  HAVING SUM(CASE WHEN cc.fecha BETWEEN fecha1 AND fecha2 THEN 1 ELSE 0 END) = 0;
END //
DELIMITER ;*/