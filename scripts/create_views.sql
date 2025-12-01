CREATE VIEW vtopVentasMes AS
SELECT	
p.id_producto,
s.sku AS SKU_Producto, 
m.nombre_producto AS Nombre_Modelo, 
SUM(pd.cantidad_producto) AS Unidades_Vendidas, 
SUM(pd.cantidad_producto * p.precio_unitario) AS Ingreso_Total_Generado
FROM 
Modelos m JOIN Productos p ON m.id_modelo=p.id_modelo 
JOIN Sku s on p.id_sku=s.id_sku 
JOIN Pedidos_Detalles pd ON p.id_producto=pd.id_producto 
JOIN Pedidos pe ON pd.id_pedido=pe.id_pedido  
WHERE 
MONTH(pe.fecha_pedido) = MONTH(CURRENT_DATE) AND YEAR(pe.fecha_pedido) = YEAR(CURRENT_DATE) AND pe.id_estado_pedido != (
	SELECT id_estado_pedido 
	FROM Estados_Pedidos 
	WHERE estado_pedido = 'Cancelado'
)

GROUP BY 
p.id_producto,s.sku 
ORDER BY 
Unidades_Vendidas DESC LIMIT 10;



CREATE OR REPLACE VIEW vInventarioBajo AS
SELECT
Suc.id_sucursal,
Suc.nombre_sucursal,
P.id_producto,
M.nombre_producto,
SP.stock_actual,
SP.stock_ideal,
(SP.stock_ideal - SP.stock_actual) AS Unidades_Faltantes
FROM Sucursales_Productos SP
JOIN Sucursales Suc ON SP.id_sucursal = Suc.id_sucursal
JOIN Productos P ON SP.id_producto = P.id_producto
JOIN Modelos M ON P.id_modelo = M.id_modelo
WHERE SP.stock_actual < SP.stock_ideal
AND P.activo_producto = TRUE
AND Suc.activo_sucursal = TRUE
ORDER BY Unidades_Faltantes DESC;



CREATE OR REPLACE VIEW vPedidosPorEstado AS
SELECT
EP.estado_pedido,
COUNT(P.id_pedido) AS Total_Pedidos
FROM Pedidos P
JOIN Estados_Pedidos EP ON P.id_estado_pedido = EP.id_estado_pedido
GROUP BY EP.estado_pedido
ORDER BY Total_Pedidos DESC;



CREATE OR REPLACE VIEW vFacturacionDiaria AS
SELECT
fecha_emision AS Dia,
COUNT(id_factura) AS Numero_Facturas,
SUM(subtotal) AS Subtotal_Diario,
SUM(impuestos) AS Impuestos_Diarios,
SUM(total) AS Total_Facturado_Diario
FROM Facturas
GROUP BY fecha_emision
ORDER BY fecha_emision DESC;


CREATE OR REPLACE VIEW vMargenPorCategoria AS
SELECT
C.nombre_categoria,
SUM(PD.cantidad_producto) AS Unidades_Vendidas,
SUM(PD.cantidad_producto * P.precio_unitario) AS Ingreso_Total,
SUM(PD.cantidad_producto * P.costo_unitario) AS Costo_Total,
SUM(PD.cantidad_producto * (P.precio_unitario - P.costo_unitario)) AS Margen_Bruto_Total, ROUND(SUM(PD.cantidad_producto * (P.precio_unitario - P.costo_unitario))/SUM(PD.cantidad_producto * P.precio_unitario)*100,2) AS Margen_Porcentaje
FROM Pedidos_Detalles PD
JOIN Productos P ON PD.id_producto = P.id_producto
JOIN Modelos M ON P.id_modelo = M.id_modelo
JOIN Categorias C ON M.id_categoria = C.id_categoria
JOIN Pedidos Pe ON PD.id_pedido = Pe.id_pedido
WHERE Pe.id_estado_pedido IN (
	SELECT id_estado_pedido
	FROM Estados_Pedidos
	WHERE estado_pedido != 'Cancelado'
)
GROUP BY C.nombre_categoria
ORDER BY Margen_Bruto_Total DESC;



CREATE OR REPLACE VIEW vDevolucionesPorMotivo AS
SELECT
motivo_devolucion,
COUNT(id_devolucion_detalle) AS Cantidad_Devoluciones,
SUM(cantidad_devuelta) AS Unidades_Totales_Devueltas
FROM Devoluciones_Detalles
GROUP BY motivo_devolucion
ORDER BY Cantidad_Devoluciones DESC;


CREATE OR REPLACE VIEW vTicketsPromedio AS
SELECT
-- Calculamos el promedio del total de cada pedido
AVG(Ventas_Por_Pedido.Total_Pedido) AS Ticket_Promedio,
-- Información adicional útil
COUNT(Ventas_Por_Pedido.id_pedido) AS Numero_Total_Pedidos,
SUM(Ventas_Por_Pedido.Total_Pedido) AS Ingresos_Totales
FROM (
	-- calcula el valor total de cada pedido individual
	SELECT
	PD.id_pedido,
	SUM(PD.cantidad_producto * P.precio_unitario) AS Total_Pedido
	FROM Pedidos_Detalles PD
	JOIN Productos P ON PD.id_producto = P.id_producto
	JOIN Pedidos Pe ON PD.id_pedido = Pe.id_pedido
	WHERE Pe.id_estado_pedido != (
		SELECT id_estado_pedido
		FROM Estados_Pedidos
		WHERE estado_pedido = 'Cancelado'
	)
	GROUP BY PD.id_pedido
) AS Ventas_Por_Pedido;



CREATE OR REPLACE VIEW vClientesRecurrentes AS
SELECT
C.id_cliente,
U.nombre_usuario,
CONCAT(U.nombre_primero, ' ', U.apellido_paterno, ' ', U.apellido_materno) AS Nombre_Completo,
U.correo,
COUNT(PC.id_pedido) AS Numero_De_Pedidos
FROM Clientes C
JOIN Usuarios U ON C.id_usuario = U.id_usuario
JOIN Pedidos_Clientes PC ON C.id_cliente = PC.id_cliente
JOIN Pedidos Pe ON PC.id_pedido = Pe.id_pedido
WHERE Pe.id_estado_pedido != (
	SELECT id_estado_pedido
	FROM Estados_Pedidos
	WHERE estado_pedido = 'Cancelado'
)
GROUP BY C.id_cliente, U.nombre_usuario, Nombre_Completo, U.correo
HAVING COUNT(PC.id_pedido) > 1
ORDER BY Numero_De_Pedidos DESC;

