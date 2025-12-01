CREATE TABLE IF NOT EXISTS Productos_Actualizados (
    id_producto INT PRIMARY KEY,
    id_sku INT NOT NULL UNIQUE,
    id_modelo INT NOT NULL,
    id_material INT NOT NULL,
    precio_unitario DECIMAL(10,2) NOT NULL,
    descuento_productoANTES TINYINT NULL,
    descuento_productoDESPUES TINYINT NULL,
    costo_unitario DECIMAL(10,2) NOT NULL,
fecha_actualizacion_producto TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$

CREATE OR REPLACE TRIGGER productoAIUD
AFTER UPDATE ON Productos
FOR EACH ROW
BEGIN
    IF NEW.descuento_producto <> OLD.descuento_producto THEN
INSERT INTO Productos_Actualizados (
            id_producto,
            id_sku,
            id_modelo,
            id_material,
            precio_unitario,
            descuento_productoANTES,
            descuento_productoDESPUES,
            costo_unitario        )
        VALUES (
            NEW.id_producto,
            NEW.id_sku,
            NEW.id_modelo,
            NEW.id_material,
            OLD.precio_unitario,
            OLD.descuento_producto,
            NEW.descuento_producto,
            NEW.costo_unitario        );
    END IF;
END $$

DELIMITER ;




DELIMITER $$

CREATE OR REPLACE TRIGGER estandarizar_sku
BEFORE INSERT ON Sku
FOR EACH ROW
BEGIN
    SET NEW.sku = UPPER(TRIM(NEW.sku));
    WHILE LOCATE(' ', NEW.sku) > 0 DO
        SET NEW.sku = REPLACE(NEW.sku, ' ', '');
    END WHILE;
    IF NEW.sku NOT LIKE 'AUR-%' THEN
        SET NEW.sku = CONCAT('AUR-', NEW.sku);
    END IF;
    IF NEW.sku NOT REGEXP '^AUR-[0-9]{3}[A-Z]$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Formato inválido. Debe ser AUR-999X';
    END IF;
    IF LENGTH(NEW.sku) <> 8 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Formato inválido. Debe contener 8 caracteres.';
    END IF;
END $$

CREATE OR REPLACE TRIGGER estandarizar_sku_actualizacion
BEFORE UPDATE ON Sku
FOR EACH ROW
BEGIN
    SET NEW.sku = UPPER(TRIM(NEW.sku));
    WHILE LOCATE(' ', NEW.sku) > 0 DO
        SET NEW.sku = REPLACE(NEW.sku, ' ', '');
    END WHILE;
    IF NEW.sku NOT LIKE 'AUR-%' THEN
        SET NEW.sku = CONCAT('AUR-', NEW.sku);
    END IF;
    IF NEW.sku NOT REGEXP '^AUR-[0-9]{3}[A-Z]$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Formato inválido. Debe ser AUR-999X';
    END IF;
    IF LENGTH(NEW.sku) <> 8 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Formato inválido. Debe contener 8 caracteres.';
    END IF;
END $$

DELIMITER ;




CREATE TABLE IF NOT EXISTS Pedidos_Auditoria_Estados (
    id_auditoria INT PRIMARY KEY AUTO_INCREMENT,
    id_pedido INT NOT NULL,
    fecha_pedido_auditoria DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_estado_pedido_old INT NOT NULL,
    estado_pedido_old VARCHAR(20) NOT NULL,
    id_estado_pedido_new INT NOT NULL,
    estado_pedido_new VARCHAR(20) NOT NULL,
    id_usuario INT NOT NULL,  -- Esta columna almacenará el id_usuario
    FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido),
    FOREIGN KEY (id_estado_pedido_old) REFERENCES Estados_Pedidos(id_estado_pedido),
    FOREIGN KEY (id_estado_pedido_new) REFERENCES Estados_Pedidos(id_estado_pedido),
    FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario)  -- Referencia a la tabla Usuarios
);


DELIMITER $$

CREATE OR REPLACE TRIGGER auditoria_pedidos
AFTER UPDATE ON Pedidos
FOR EACH ROW
BEGIN
    IF NEW.id_estado_pedido <> OLD.id_estado_pedido THEN
        INSERT INTO Pedidos_Auditoria_Estados (
            id_pedido,
            id_estado_pedido_old,
            estado_pedido_old,
            id_estado_pedido_new,
            estado_pedido_new,
            id_usuario
        )
        VALUES (
            NEW.id_pedido,
            OLD.id_estado_pedido,
            (SELECT estado_pedido FROM Estados_Pedidos WHERE id_estado_pedido = OLD.id_estado_pedido),
            NEW.id_estado_pedido,
            (SELECT estado_pedido FROM Estados_Pedidos WHERE id_estado_pedido = NEW.id_estado_pedido),
            1
        );
    END IF;
END $$

DELIMITER ;




DROP TRIGGER IF EXISTS valida_stock_sobreventa;

DELIMITER $$
CREATE TRIGGER valida_stock_sobreventa
BEFORE INSERT ON Pedidos_Detalles
FOR EACH ROW
BEGIN
    DECLARE IDproducto INT;
    DECLARE IDsucursal INT DEFAULT NULL;
    DECLARE stockSucursalProducto INT;
    DECLARE productoSKU VARCHAR(12);
    DECLARE mensaje VARCHAR(500);
    
    SET IDproducto = NEW.id_producto;

    -- SIEMPRE asignar automáticamente la sucursal con mayor stock disponible para este producto
    -- Primero intentar encontrar una sucursal activa con stock suficiente
    SELECT sp.id_sucursal INTO IDsucursal
    FROM Sucursales_Productos sp
    JOIN Sucursales s ON s.id_sucursal = sp.id_sucursal
    WHERE sp.id_producto = IDproducto
      AND s.activo_sucursal = 1
      AND sp.stock_actual >= NEW.cantidad_producto
    ORDER BY sp.stock_actual DESC
    LIMIT 1;

    -- Si no se encontró una con stock suficiente, buscar cualquier sucursal activa con el producto
    IF IDsucursal IS NULL THEN
        SELECT sp.id_sucursal INTO IDsucursal
        FROM Sucursales_Productos sp
        JOIN Sucursales s ON s.id_sucursal = sp.id_sucursal
        WHERE sp.id_producto = IDproducto
          AND s.activo_sucursal = 1
        ORDER BY sp.stock_actual DESC
        LIMIT 1;
    END IF;

    -- Si aún no se encontró, lanzar error ANTES de intentar asignar NULL
    IF IDsucursal IS NULL THEN
        SELECT s.sku INTO productoSKU 
        FROM Sku s 
        JOIN Productos p ON s.id_sku = p.id_sku 
        WHERE p.id_producto = NEW.id_producto 
        LIMIT 1;
        
        SET mensaje = CONCAT('El producto ', COALESCE(productoSKU, 'ID: ' + CAST(IDproducto AS CHAR)), ' no está registrado en el inventario de ninguna sucursal activa.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = mensaje;
    END IF;

    -- Asignar automáticamente la sucursal con mayor stock (ignorando el valor que venga)
    SET NEW.id_sucursal = IDsucursal;

    -- Validar stock
    SELECT stock_actual INTO stockSucursalProducto 
    FROM Sucursales_Productos 
    WHERE id_producto = IDproducto AND id_sucursal = IDsucursal
    LIMIT 1;

    IF stockSucursalProducto IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no está registrado en la sucursal seleccionada.';
    END IF;

    SELECT s.sku INTO productoSKU 
    FROM Sku s 
    JOIN Productos p ON s.id_sku = p.id_sku 
    WHERE p.id_producto = NEW.id_producto 
    LIMIT 1;

    IF NEW.cantidad_producto > stockSucursalProducto THEN
        SET mensaje = CONCAT('Stock insuficiente para ', COALESCE(productoSKU, 'producto'), ' | Disponible: ', stockSucursalProducto, ' | Solicitado: ', NEW.cantidad_producto);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = mensaje;
    END IF;
END $$
DELIMITER ;






CREATE TABLE IF NOT EXISTS auditoria_facturas (
id_factura INT NOT NULL,
id_estado_factura INT NOT NULL,
estado_factura_inicio ENUM('Emitida','Pagada','Cancelada','Parcial','En revisión') NOT NULL,
estado_factura_modificado ENUM('Emitida','Pagada','Cancelada','Parcial','En revisión') NOT NULL,
fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$
CREATE OR REPLACE TRIGGER factura_AIUD
AFTER UPDATE ON Estados_Facturas
FOR EACH ROW
BEGIN
IF OLD.estado_factura <> NEW.estado_factura THEN
       		INSERT INTO auditoria_facturas (id_factura, id_estado_factura, estado_factura_inicio, estado_factura_modificado)
        		VALUES (NEW.id_factura, NEW.id_estado_factura, OLD.estado_factura, NEW.estado_factura);
    	END IF;
END $$
DELIMITER ;




CREATE TABLE IF NOT EXISTS Auditoria_Pagos (
id_pago INT NOT NULL,
id_metodo_pago INT NOT NULL,
id_montos_pago INT NOT NULL,
monto_metodo_pago_inicial INT NOT NULL,
monto_metodo_pago_modificado INT NOT NULL,
fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$
CREATE OR REPLACE TRIGGER pago_AUDAI
AFTER UPDATE ON Montos_Pagos
FOR EACH ROW
BEGIN
IF NEW.monto_metodo_pago <> OLD.monto_metodo_pago THEN
       		INSERT INTO Auditoria_Pagos (id_pago, id_metodo_pago,
id_montos_pago, monto_metodo_pago_inicial, monto_metodo_pago_modificado)
        	VALUES (NEW.id_pago, NEW.id_metodo_pago, NEW.id_montos_pago, OLD.monto_metodo_pago, NEW.monto_metodo_pago);
    	END IF;
END $$
DELIMITER ;




CREATE TABLE IF NOT EXISTS auditoria_devoluciones_completadas (
	id_devolucion INT NOT NULL,
	id_pedido_detalle INT NOT NULL,
	cantidad_devuelta INT NOT NULL,
	id_producto INT NOT NULL,
	motivo_devolucion VARCHAR(200) NOT NULL,
	fecha_devolucion_completada DATE DEFAULT (CURRENT_DATE)
);

DELIMITER $$
CREATE OR REPLACE TRIGGER devolucionAIUD
AFTER UPDATE ON Devoluciones_Detalles
FOR EACH ROW
BEGIN
IF OLD.id_estado_devolucion <> NEW.id_estado_devolucion  AND NEW.id_estado_devolucion = (SELECT id_estado_devolucion FROM Estados_Devoluciones WHERE estado_devolucion = 'Completado') 
THEN
        		INSERT INTO auditoria_devoluciones_completadas (id_devolucion, id_pedido_detalle, cantidad_devuelta, id_producto)
        		VALUES (NEW.id_devolucion, NEW.id_pedido_detalle, NEW.cantidad_devuelta, (SELECT id_producto FROM Pedidos_Detalles WHERE id_pedido_detalle = NEW.id_pedido_detalle), NEW.motivo_devolucion);
   	END IF;
END $$
DELIMITER ;





DELIMITER $$

CREATE OR REPLACE TRIGGER reingresoAutoDevolucion
AFTER UPDATE ON Devoluciones_Detalles
FOR EACH ROW
BEGIN
    DECLARE idCompletado INT;
    -- Obtener el id correspondiente al estado "Completado"
    SELECT id_estado_devolucion INTO idCompletado
    FROM Estados_Devoluciones
    WHERE estado_devolucion = 'Completado'
    LIMIT 1;

    -- Verificar cambio de estado y que el nuevo sea "Completado"
    IF OLD.id_estado_devolucion <> NEW.id_estado_devolucion
       AND NEW.id_estado_devolucion = idCompletado THEN

        UPDATE Devoluciones_Detalles dd
        JOIN Pedidos_Detalles pd 
            ON dd.id_pedido_detalle = pd.id_pedido_detalle
        JOIN Sucursales_Productos sp
            ON pd.id_producto = sp.id_producto
        SET sp.stock_actual = sp.stock_actual + dd.cantidad_devuelta
        WHERE dd.id_devolucion_detalle = NEW.id_devolucion_detalle
          AND sp.id_sucursal = pd.id_sucursal; 
    END IF;
END $$
DELIMITER ;




CREATE TABLE IF NOT EXISTS Log_Alertas (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT,
    id_sucursal INT,
    stock_actual INT,
    stock_ideal INT,
    fecha DATETIME
);

DELIMITER $$

CREATE OR REPLACE TRIGGER alerta_stock_bajo
AFTER UPDATE ON Sucursales_Productos
FOR EACH ROW
BEGIN
    IF NEW.stock_actual < NEW.stock_ideal THEN
        INSERT INTO Log_Alertas (id_producto, id_sucursal, stock_actual, stock_ideal, fecha)
        VALUES (NEW.id_producto, NEW.id_sucursal, NEW.stock_actual, NEW.stock_ideal, NOW());
    END IF;
END $$

DELIMITER ;


DELIMITER $$

-- Eliminar el trigger anterior si existe
DROP TRIGGER IF EXISTS validar_flujo;

CREATE TRIGGER validar_flujo
BEFORE UPDATE ON Pedidos
FOR EACH ROW
BEGIN
    DECLARE idConfirmado INT;
    DECLARE idProcesado INT;
    DECLARE idCompletado INT;
    DECLARE idCancelado INT;

    SELECT id_estado_pedido INTO idConfirmado FROM Estados_Pedidos WHERE estado_pedido = 'Confirmado';
    SELECT id_estado_pedido INTO idProcesado FROM Estados_Pedidos WHERE estado_pedido = 'Procesado';
    SELECT id_estado_pedido INTO idCompletado FROM Estados_Pedidos WHERE estado_pedido = 'Completado';
    SELECT id_estado_pedido INTO idCancelado FROM Estados_Pedidos WHERE estado_pedido = 'Cancelado';

    IF NEW.id_estado_pedido <> OLD.id_estado_pedido THEN
        IF NOT (
            -- Confirmado puede ir a Procesado o directamente a Cancelado
            (OLD.id_estado_pedido = idConfirmado AND NEW.id_estado_pedido = idProcesado)
            OR
            (OLD.id_estado_pedido = idConfirmado AND NEW.id_estado_pedido = idCancelado)
            OR
            -- Procesado puede ir a Completado o Cancelado
            (OLD.id_estado_pedido = idProcesado AND NEW.id_estado_pedido = idCompletado)
            OR
            (OLD.id_estado_pedido = idProcesado AND NEW.id_estado_pedido = idCancelado)
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: El flujo de estados no es válido';
        END IF;
    END IF;
END$$

DELIMITER ;




DELIMITER $$
CREATE OR REPLACE TRIGGER estandariza_municipios
BEFORE INSERT ON Municipios_Direcciones
FOR EACH ROW
BEGIN
    DECLARE municipio_insertado VARCHAR(100);
    DECLARE municipio_final VARCHAR(100) DEFAULT '';
    SET municipio_insertado = TRIM(NEW.municipio_direccion);
    WHILE LOCATE(' ', municipio_insertado) > 0 DO
        SET municipio_final = CONCAT(
            municipio_final,
            UPPER(LEFT(SUBSTRING_INDEX(municipio_insertado, ' ', 1), 1)),
            LOWER(SUBSTRING(SUBSTRING_INDEX(municipio_insertado, ' ', 1), 2)),
            ' '
        );
        SET municipio_insertado = SUBSTRING(municipio_insertado, LOCATE(' ', municipio_insertado) + 1);
    END WHILE;
    SET municipio_final = CONCAT(
        municipio_final,
        UPPER(LEFT(municipio_insertado, 1)),
        LOWER(SUBSTRING(municipio_insertado, 2))
    );
    SET NEW.municipio_direccion = municipio_final;
END $$
DELIMITER ;

DELIMITER $$
CREATE OR REPLACE TRIGGER estandariza_municipios_Actualizacion
BEFORE UPDATE ON Municipios_Direcciones
FOR EACH ROW
BEGIN
    DECLARE municipio_insertado VARCHAR(100);
    DECLARE municipio_final VARCHAR(100) DEFAULT '';
    SET municipio_insertado = TRIM(NEW.municipio_direccion);
    WHILE LOCATE(' ', municipio_insertado) > 0 DO
        SET municipio_final = CONCAT(
            municipio_final,
            UPPER(LEFT(SUBSTRING_INDEX(municipio_insertado, ' ', 1), 1)),
            LOWER(SUBSTRING(SUBSTRING_INDEX(municipio_insertado, ' ', 1), 2)),
            ' '
        );
        SET municipio_insertado = SUBSTRING(municipio_insertado, LOCATE(' ', municipio_insertado) + 1);
    END WHILE;
    SET municipio_final = CONCAT(
        municipio_final,
        UPPER(LEFT(municipio_insertado, 1)),
        LOWER(SUBSTRING(municipio_insertado, 2))
    );
    SET NEW.municipio_direccion = municipio_final;
END $$
DELIMITER ;




DELIMITER $$
CREATE OR REPLACE TRIGGER validar_rfc_empresa
BEFORE INSERT ON Empresas
FOR EACH ROW
BEGIN
SET NEW.rfc_empresa = UPPER(NEW.rfc_empresa);
IF LENGTH(NEW.rfc_empresa) <>12 THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El RFC debe contener 12 carácteres';
END IF;
END $$
DELIMITER ;




DELIMITER $$
CREATE OR REPLACE TRIGGER validar_correo_empresa
BEFORE INSERT ON Empresas
FOR EACH ROW
BEGIN
IF NEW.correo_empresa NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Correo inválido';
END IF;
END $$
DELIMITER ;


DELIMITER $$
CREATE OR REPLACE TRIGGER estandariza_genero
BEFORE INSERT ON Generos
FOR EACH ROW
BEGIN
	SET NEW.genero = TRIM(NEW.genero);
	SET NEW.genero = CONCAT(UPPER(SUBSTR(NEW.genero, 1, 1)),LOWER(SUBSTR(NEW.genero, 2)));
END $$
DELIMITER ;
DELIMITER $$
CREATE OR REPLACE TRIGGER estandariza_genero_Actualizacion
BEFORE UPDATE ON Generos
FOR EACH ROW
BEGIN
	SET NEW.genero = TRIM(NEW.genero);
	SET NEW.genero = CONCAT(UPPER(SUBSTR(NEW.genero, 1, 1)),LOWER(SUBSTR(NEW.genero, 2)));
END $$
DELIMITER ;

DELIMITER $$

CREATE OR REPLACE TRIGGER actualizar_stock
AFTER INSERT ON Pedidos_Detalles
FOR EACH ROW
BEGIN
    DECLARE v_stock_actual INT;

    SELECT stock_actual
    INTO v_stock_actual
    FROM Sucursales_Productos
    WHERE id_sucursal = NEW.id_sucursal
      AND id_producto = NEW.id_producto
    LIMIT 1;

    IF v_stock_actual < NEW.cantidad_producto THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR_STOCK_INSUFICIENTE';
    END IF;

    UPDATE Sucursales_Productos
    SET stock_actual = stock_actual - NEW.cantidad_producto
    WHERE id_sucursal = NEW.id_sucursal
      AND id_producto = NEW.id_producto;
END $$

DELIMITER ;




DELIMITER $$

CREATE OR REPLACE TRIGGER validar_stock_no_negativo_insert
BEFORE INSERT ON Sucursales_Productos
FOR EACH ROW
BEGIN
    DECLARE v_mensaje VARCHAR(500);
    -- Validar que el stock_actual no sea negativo al insertar
    IF NEW.stock_actual < 0 THEN
        SET v_mensaje = CONCAT('Error: El stock no puede ser negativo. Intento de insertar stock: ', NEW.stock_actual);
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = v_mensaje;
    END IF;
END $$

DELIMITER ;

DELIMITER $$

CREATE OR REPLACE TRIGGER validar_stock_no_negativo_update
BEFORE UPDATE ON Sucursales_Productos
FOR EACH ROW
BEGIN
    DECLARE v_mensaje VARCHAR(500);
    -- Validar que el stock_actual no sea negativo al actualizar
    IF NEW.stock_actual < 0 THEN
        SET v_mensaje = CONCAT('Error: El stock no puede ser negativo. Stock actual: ', OLD.stock_actual, ', intento de actualizar a: ', NEW.stock_actual);
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = v_mensaje;
    END IF;
END $$

DELIMITER ;

DELIMITER $$

CREATE OR REPLACE TRIGGER validar_stock_maximo_insert
BEFORE INSERT ON Sucursales_Productos
FOR EACH ROW
BEGIN
    DECLARE v_mensaje VARCHAR(500);
    -- Validar que el stock_actual no exceda el stock_maximo al insertar
    IF NEW.stock_actual > NEW.stock_maximo THEN
        SET v_mensaje = CONCAT('Error: El stock actual (', NEW.stock_actual, ') no puede exceder el stock máximo (', NEW.stock_maximo, ').');
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = v_mensaje;
    END IF;
END $$

DELIMITER ;

DELIMITER $$

CREATE OR REPLACE TRIGGER validar_stock_maximo_update
BEFORE UPDATE ON Sucursales_Productos
FOR EACH ROW
BEGIN
    DECLARE v_mensaje VARCHAR(500);
    -- Validar que el stock_actual no exceda el stock_maximo al actualizar
    IF NEW.stock_actual > NEW.stock_maximo THEN
        SET v_mensaje = CONCAT('Error: El stock actual (', NEW.stock_actual, ') no puede exceder el stock máximo (', NEW.stock_maximo, '). Stock anterior: ', OLD.stock_actual);
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = v_mensaje;
    END IF;
END $$

DELIMITER ;




DELIMITER $$

CREATE OR REPLACE TRIGGER trg_asignar_imagen_default
AFTER INSERT ON Productos
FOR EACH ROW
BEGIN
    INSERT INTO Imagenes_Productos (
        id_producto,
        url_imagen
    ) VALUES (
        NEW.id_producto,
        '/images/defaults/joyeria-default.png'
    );
END $$

DELIMITER ;



DELIMITER $$
CREATE OR REPLACE TRIGGER actualizar_clasificacion
AFTER INSERT ON Pedidos_Clientes
FOR EACH ROW
BEGIN
DECLARE IDCliente INT;
DECLARE IDUsuario INT;
DECLARE IDClasifActual INT;
DECLARE TotalCompras DECIMAL(10,2) DEFAULT 0;
DECLARE TotalReembolsos DECIMAL(10,2) DEFAULT 0;
DECLARE TotalGastado DECIMAL(10,2) DEFAULT 0;
DECLARE NuevaClasificacion INT;
DECLARE CompraMinActual DECIMAL(10,2);
DECLARE CompraMinNueva DECIMAL(10,2);
DECLARE EsEmpleado TINYINT DEFAULT 0;
DECLARE IDRolCliente INT;

SET IDCliente=NEW.id_cliente;

SELECT id_usuario INTO IDUsuario FROM Clientes WHERE id_cliente=IDCliente;
SELECT id_roles INTO IDRolCliente FROM Roles WHERE nombre_rol='Cliente' LIMIT 1;

IF IDUsuario IS NOT NULL AND IDRolCliente IS NOT NULL THEN
SELECT COUNT(*) INTO EsEmpleado
FROM Usuarios_Roles ur
WHERE ur.id_usuario=IDUsuario
AND ur.activo_usuario_rol=1
AND ur.id_roles<>IDRolCliente;
END IF;

IF EsEmpleado=1 THEN
UPDATE Clientes SET id_clasificacion=4 WHERE id_cliente=IDCliente;
ELSE
SELECT COALESCE(SUM(pd.cantidad_producto*pr.precio_unitario),0) INTO TotalCompras
FROM Pedidos_Clientes pc
JOIN Pedidos_Detalles pd ON pc.id_pedido=pd.id_pedido
JOIN Productos pr ON pr.id_producto=pd.id_producto
WHERE pc.id_cliente=IDCliente;

SELECT COALESCE(SUM(dd.cantidad_devuelta*pr2.precio_unitario),0) INTO TotalReembolsos
FROM Devoluciones_Detalles dd
JOIN Devoluciones d ON dd.id_devolucion=d.id_devolucion
JOIN Pedidos_Detalles pd2 ON dd.id_pedido_detalle=pd2.id_pedido_detalle
JOIN Pedidos_Clientes pc2 ON pd2.id_pedido=pc2.id_pedido
JOIN Productos pr2 ON pr2.id_producto=pd2.id_producto
JOIN Tipos_Devoluciones td ON dd.id_tipo_devoluciones=td.id_tipo_devoluciones
JOIN Estados_Devoluciones ed ON dd.id_estado_devolucion=ed.id_estado_devolucion
WHERE pc2.id_cliente=IDCliente
AND td.tipo_devolucion='Reembolso'
AND ed.estado_devolucion='Completado';

SET TotalGastado=TotalCompras-TotalReembolsos;

SELECT c.id_clasificacion,c.compra_min INTO NuevaClasificacion,CompraMinNueva
FROM Clasificaciones c
WHERE c.id_clasificacion<>4
AND (c.compra_min IS NULL OR TotalGastado>=c.compra_min)
AND (c.compra_max IS NULL OR TotalGastado<=c.compra_max)
ORDER BY c.compra_min ASC
LIMIT 1;

IF NuevaClasificacion IS NOT NULL THEN
SELECT id_clasificacion INTO IDClasifActual FROM Clientes WHERE id_cliente=IDCliente;

IF IDClasifActual IS NULL THEN
UPDATE Clientes SET id_clasificacion=NuevaClasificacion WHERE id_cliente=IDCliente;
ELSE
SELECT compra_min INTO CompraMinActual FROM Clasificaciones WHERE id_clasificacion=IDClasifActual;
IF CompraMinActual IS NULL OR CompraMinNueva>CompraMinActual THEN
UPDATE Clientes SET id_clasificacion=NuevaClasificacion WHERE id_cliente=IDCliente;
END IF;
END IF;
END IF;
END IF;
END $$

DELIMITER ;




DELIMITER $$
CREATE OR REPLACE TRIGGER autorizar_solicitud_devolucion
BEFORE INSERT ON Devoluciones
FOR EACH ROW
BEGIN
	DECLARE fechaPedido DATE;
	SELECT DATE(fecha_pedido) INTO fechaPedido FROM Pedidos WHERE id_pedido= NEW.id_pedido;
	IF fechaPedido IS NULL THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "El pedido no existe";
	END IF;

IF NEW.fecha_devolucion - fechaPedido >30 THEN
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "No es posible devolver el producto después de 30 días";
END IF;
IF NEW.fecha_devolucion < fechaPedido THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "La fecha de la devolución es inválida.";

END IF;

END $$
DELIMITER ;



DELIMITER $$
CREATE OR REPLACE TRIGGER devolucion_pedido_valido
BEFORE INSERT ON Devoluciones
FOR EACH ROW
BEGIN
	DECLARE estadoPedido VARCHAR(20);
	SELECT ep.estado_pedido INTO estadoPedido FROM Pedidos p JOIN Estados_Pedidos ep ON p.id_estado_pedido=ep.id_estado_pedido WHERE p.id_pedido = NEW.id_pedido;
	IF estadoPedido <> 'Completado' THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "ERROR: El pedido no ha sido completado";
	END IF;
	IF estadoPedido = 'Cancelado' THEN 
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: No se puede devolver un pedido cancelado';
	END IF;



END $$
DELIMITER ;


DELIMITER $$
CREATE OR REPLACE TRIGGER devolucion_detalles_pedido_valido
BEFORE INSERT ON Devoluciones_Detalles
FOR EACH ROW
BEGIN
	DECLARE existePedidoDetalle INT;
	DECLARE fechaPedido DATE;
	DECLARE fechaDevolucion DATE;
DECLARE estadoPedido VARCHAR(20);
DECLARE cantidadYaDevuelta INT;
DECLARE cantidadProductoCompra INT;


	-- Valida la existencia de ese detalle de pedidos
SELECT COUNT(*) INTO existePedidoDetalle  FROM Pedidos_Detalles  WHERE id_pedido_detalle = NEW.id_pedido_detalle;
IF existePedidoDetalle=0 THEN
SIGNAL SQLSTATE '45000'  SET MESSAGE_TEXT = 'ERROR: El detalle del pedido no existe.';
END IF;


SELECT DATE(fecha_pedido) INTO fechaPedido FROM Pedidos p JOIN Pedidos_Detalles pd ON p.id_pedido=pd.id_pedido WHERE id_pedido_detalle = NEW.id_pedido_detalle;

SELECT fecha_devolucion INTO fechaDevolucion FROM Devoluciones WHERE id_devolucion= NEW.id_devolucion limit 1;

-- Se comprueba que la fecha de devolución este dentro del rango aceptable, y sea mayor que la fecha de pedido

IF DATEDIFF(fechaDevolucion, fechaPedido) > 30 THEN
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "No es posible devolver el producto después de 30 días";
END IF;

IF fechaDevolucion < fechaPedido THEN
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "La fecha de la devolución es inválida.";
END IF;


-- Validar que el pedido este completado para proceder

	SELECT ep.estado_pedido INTO estadoPedido FROM Pedidos p JOIN Estados_Pedidos ep ON ep.id_estado_pedido = p.id_estado_pedido JOIN Pedidos_Detalles pd ON pd.id_pedido = p.id_pedido WHERE pd.id_pedido_detalle = NEW.id_pedido_detalle LIMIT 1;
	IF estadoPedido <> 'Completado' THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "ERROR: El pedido no ha sido completado";
	END IF;

-- Verifica que no devolvamos de más productos de los que se compraron

SELECT SUM(cantidad_devuelta) INTO cantidadYaDevuelta FROM Devoluciones_Detalles WHERE id_pedido_detalle = NEW.id_pedido_detalle;

SELECT cantidad_producto INTO cantidadProductoCompra FROM Pedidos_Detalles where  id_pedido_detalle = NEW.id_pedido_detalle;

IF cantidadYaDevuelta IS NULL THEN
	SET cantidadYaDevuelta = 0;
END IF;

-- Si ya se devolvió todo
IF cantidadYaDevuelta >= cantidadProductoCompra THEN
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "ERROR: Ya se han devuelto todos los productos de este artículo. No hay más unidades disponibles para devolver.";
END IF;

-- Si la cantidad solicitada excede lo disponible
IF (cantidadYaDevuelta + NEW.cantidad_devuelta) > cantidadProductoCompra THEN
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "ERROR: La cantidad a devolver excede las unidades disponibles. Verifique cuántas unidades ya fueron devueltas.";
END IF;

END$$
DELIMITER ;




DELIMITER $$

CREATE TRIGGER clientes_asigna_clasificaciones_empleado_regular
BEFORE INSERT ON Clientes
FOR EACH ROW
BEGIN
    DECLARE v_es_empleado INT DEFAULT 0;
    DECLARE v_id_clas_empleado INT DEFAULT NULL;
    DECLARE v_id_clas_regular INT DEFAULT NULL;
    DECLARE v_id_rol_cliente INT DEFAULT NULL;

    SELECT id_roles INTO v_id_rol_cliente
    FROM Roles
    WHERE nombre_rol = 'Cliente'
    LIMIT 1;

    SELECT COUNT(*) INTO v_es_empleado
    FROM Usuarios_Roles
    WHERE id_usuario = NEW.id_usuario
      AND activo_usuario_rol = 1
      AND id_roles <> v_id_rol_cliente;

    SELECT id_clasificacion INTO v_id_clas_empleado
    FROM Clasificaciones
    WHERE nombre_clasificacion = 'Empleado'
    LIMIT 1;

    SELECT id_clasificacion INTO v_id_clas_regular
    FROM Clasificaciones
    WHERE nombre_clasificacion = 'Regular'
    LIMIT 1;

    IF v_es_empleado > 0 THEN
        SET NEW.id_clasificacion = v_id_clas_empleado;

    ELSEIF NEW.id_clasificacion IS NULL THEN
        SET NEW.id_clasificacion = v_id_clas_regular;
    END IF;

END$$

DELIMITER ;

-- ======================================================
-- TRIGGER: Validar que id_cliente no sea NULL al insertar en Pedidos_Clientes
-- ======================================================
DROP TRIGGER IF EXISTS validar_pedido_cliente_no_null;

DELIMITER $$
CREATE TRIGGER validar_pedido_cliente_no_null
BEFORE INSERT ON Pedidos_Clientes
FOR EACH ROW
BEGIN
    -- Validar que id_cliente no sea NULL
    IF NEW.id_cliente IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: No se puede asociar un pedido con un cliente NULL.';
    END IF;
    
    -- Validar que el cliente existe
    IF NOT EXISTS (
        SELECT 1 FROM Clientes WHERE id_cliente = NEW.id_cliente
    ) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR: El cliente especificado no existe.';
    END IF;
END $$
DELIMITER ;
