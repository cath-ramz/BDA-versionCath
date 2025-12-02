-- Stored Procedure para registrar pago directamente al pedido (sin factura)
DELIMITER $$

CREATE OR REPLACE PROCEDURE pagoRegistrarPedido(
    IN var_id_pedido INT,
    IN var_importe DECIMAL(10,2),
    IN var_id_metodo_pago INT
)
BEGIN
    -- Variables
    DECLARE var_pedido_existe INT;
    DECLARE var_total_pedido DECIMAL(10,2);
    DECLARE conteo_pagado_anterior DECIMAL(10,2);
    DECLARE calculo_total_acumulado DECIMAL(10,2);
    DECLARE var_id_pago_nuevo INT;
    DECLARE var_pendiente DECIMAL(10,2);
    DECLARE descuento_clasificacion DECIMAL(5,2) DEFAULT 0;
    DECLARE v_mensaje_error VARCHAR(255);

    -- Verificar que el pedido existe
    SELECT COUNT(*) INTO var_pedido_existe
    FROM Pedidos
    WHERE id_pedido = var_id_pedido;

    IF var_pedido_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: El pedido no existe.';
    END IF;

    -- Obtener descuento de clasificaciÃ³n del cliente
    SELECT COALESCE(cl.descuento_clasificacion, 0)
    INTO descuento_clasificacion
    FROM Pedidos_Clientes pc
    JOIN Clientes c ON pc.id_cliente = c.id_cliente
    LEFT JOIN Clasificaciones cl ON c.id_clasificacion = cl.id_clasificacion
    WHERE pc.id_pedido = var_id_pedido
    LIMIT 1;

    -- Calcular el total del pedido (aplicando descuentos de productos)
    SELECT COALESCE(SUM((pr.precio_unitario - (pr.precio_unitario * COALESCE(pr.descuento_producto, 0) / 100)) * pd.cantidad_producto), 0)
    INTO var_total_pedido
    FROM Pedidos_Detalles pd
    JOIN Productos pr ON pd.id_producto = pr.id_producto
    WHERE pd.id_pedido = var_id_pedido;

    -- Aplicar descuento de clasificaciÃ³n si existe
    IF descuento_clasificacion > 0 THEN
        SET var_total_pedido = var_total_pedido - (var_total_pedido * descuento_clasificacion / 100);
    END IF;

    -- Validar que se obtuvo el total
    IF var_total_pedido IS NULL OR var_total_pedido = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pudo calcular el total del pedido.';
    END IF;

    -- Validar que el importe sea mayor a 0
    IF var_importe <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El importe debe ser mayor a cero.';
    END IF;

    -- Calcular pagado anterior (solo pagos sin factura para este pedido)
    SELECT COALESCE(SUM(mp.monto_metodo_pago), 0) INTO conteo_pagado_anterior
    FROM Pagos p
    JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
    WHERE p.id_pedido = var_id_pedido AND p.id_factura IS NULL;

    -- Calcular pendiente
    SET var_pendiente = var_total_pedido - conteo_pagado_anterior;

    -- Validar que el importe no sea mayor al pendiente
    IF var_importe > var_pendiente THEN
        SET v_mensaje_error = CONCAT('El importe no puede ser mayor al pendiente (', FORMAT(var_pendiente, 2), ').');
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = v_mensaje_error;
    END IF;

    -- Insertar Pago sin factura (id_factura = NULL)
    INSERT INTO Pagos (id_factura, id_pedido, fecha_pago)
    VALUES (NULL, var_id_pedido, CURDATE());

    SET var_id_pago_nuevo = LAST_INSERT_ID();

    -- Insertar Monto
    INSERT INTO Montos_Pagos (id_metodo_pago, id_pago, monto_metodo_pago)
    VALUES (var_id_metodo_pago, var_id_pago_nuevo, var_importe);

    -- Calcular nuevo total pagado
    SET calculo_total_acumulado = conteo_pagado_anterior + var_importe;

    -- Retornar resultado
    SELECT 
        CONCAT('Pago registrado exitosamente. Total pagado: ', FORMAT(calculo_total_acumulado, 2), ' de ', FORMAT(var_total_pedido, 2)) AS Mensaje,
        calculo_total_acumulado AS Total_Pagado,
        var_total_pedido AS Total_Pedido,
        (var_total_pedido - calculo_total_acumulado) AS Pendiente;
END $$

DELIMITER ;

-- ============================================
-- STORED PROCEDURES PARA DASHBOARD DE INVENTARIO
-- ============================================

DELIMITER $$

-- Total de productos únicos en stock (activos, que tienen stock en al menos una sucursal)
-- NOTA: Este procedimiento también está en SP_extra.sql, se mantiene aquí para compatibilidad
CREATE OR REPLACE PROCEDURE sp_total_stock()
BEGIN
    SELECT COUNT(DISTINCT sp.id_producto) AS total_stock
    FROM Sucursales_Productos sp
    JOIN Productos p ON sp.id_producto = p.id_producto
    JOIN Sucursales s ON sp.id_sucursal = s.id_sucursal
    WHERE p.activo_producto = TRUE
      AND s.activo_sucursal = TRUE
      AND sp.stock_actual > 0;
END $$

-- Contar productos con stock bajo (stock_actual < stock_ideal) - productos Ãºnicos
-- IMPORTANTE: Debe usar la misma lÃ³gica que sp_total_stock (solo productos con stock > 0)
CREATE OR REPLACE PROCEDURE VistaInventarioBajoCount()
BEGIN
    SELECT COUNT(DISTINCT sp.id_producto) AS stock_bajo
    FROM Sucursales_Productos sp
    JOIN Productos p ON sp.id_producto = p.id_producto
    JOIN Sucursales s ON sp.id_sucursal = s.id_sucursal
    WHERE sp.stock_actual < sp.stock_ideal
      AND p.activo_producto = TRUE
      AND s.activo_sucursal = TRUE
      AND sp.stock_actual > 0;  -- IMPORTANTE: Solo contar productos con stock > 0
END $$

-- Estado de stock: solo normal y bajo (productos Ãºnicos)
-- Devuelve 2 result sets: bajo, normal
-- IMPORTANTE: Normal + Bajo debe sumar el total de productos en stock
-- LÃ³gica: 
--   - Bajo: Un producto se marca como "Bajo" si en AL MENOS UNA sucursal tiene stock_actual < stock_ideal
--   - Normal: Un producto se marca como "Normal" si en TODAS sus sucursales tiene stock_actual >= stock_ideal
CREATE OR REPLACE PROCEDURE VistaEstadoStock()
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_bajo INT DEFAULT 0;
    DECLARE v_normal INT DEFAULT 0;
    
    -- Calcular total de productos Ãºnicos en stock (con stock > 0 en al menos una sucursal)
    SELECT COUNT(DISTINCT sp.id_producto) INTO v_total
    FROM Sucursales_Productos sp
    JOIN Productos p ON sp.id_producto = p.id_producto
    JOIN Sucursales s ON sp.id_sucursal = s.id_sucursal
    WHERE p.activo_producto = TRUE
      AND s.activo_sucursal = TRUE
      AND sp.stock_actual > 0;
    
    -- Calcular productos con stock bajo
    -- Un producto estÃ¡ "Bajo" si en AL MENOS UNA sucursal tiene stock_actual < stock_ideal
    SELECT COUNT(DISTINCT sp.id_producto) INTO v_bajo
    FROM Sucursales_Productos sp
    JOIN Productos p ON sp.id_producto = p.id_producto
    JOIN Sucursales s ON sp.id_sucursal = s.id_sucursal
    WHERE sp.stock_actual < sp.stock_ideal
      AND p.activo_producto = TRUE
      AND s.activo_sucursal = TRUE
      AND sp.stock_actual > 0;  -- Solo productos con stock > 0
    
    -- Calcular normal como total - bajo para asegurar consistencia
    -- Normal = productos que NO tienen stock bajo en ninguna sucursal
    SET v_normal = GREATEST(0, v_total - v_bajo);
    
    -- Devolver resultado: primero bajo, luego normal
    SELECT v_bajo AS bajo;
    SELECT v_normal AS normal;
END $$

DELIMITER ;

-- ============================================
-- STORED PROCEDURES PARA REPORTES DE GESTOR DE SUCURSAL
-- ============================================

DELIMITER $$    

-- Ventas totales de una sucursal en un rango de fechas
CREATE OR REPLACE PROCEDURE gestor_ventas_totales_sucursal(
    IN var_id_sucursal INT,
    IN var_fecha_desde DATE,
    IN var_fecha_hasta DATE
)
BEGIN
    SELECT COALESCE(SUM(pd.cantidad_producto * pr.precio_unitario), 0) AS total_ventas
    FROM Pedidos_Detalles pd
    JOIN Productos pr ON pd.id_producto = pr.id_producto
    JOIN Pedidos pe ON pd.id_pedido = pe.id_pedido
    JOIN Estados_Pedidos ep ON pe.id_estado_pedido = ep.id_estado_pedido
    WHERE pd.id_sucursal = var_id_sucursal
      AND DATE(pe.fecha_pedido) BETWEEN var_fecha_desde AND var_fecha_hasta
      AND ep.estado_pedido != 'Cancelado';
END $$

DELIMITER $$
-- Total de pedidos de una sucursal en un rango de fechas
CREATE OR REPLACE PROCEDURE gestor_pedidos_count_sucursal(
    IN var_id_sucursal INT,
    IN var_fecha_desde DATE,
    IN var_fecha_hasta DATE
)
BEGIN
    SELECT COUNT(DISTINCT pd.id_pedido) AS total_pedidos
    FROM Pedidos_Detalles pd
    JOIN Pedidos pe ON pd.id_pedido = pe.id_pedido
    JOIN Estados_Pedidos ep ON pe.id_estado_pedido = ep.id_estado_pedido
    WHERE pd.id_sucursal = var_id_sucursal
      AND DATE(pe.fecha_pedido) BETWEEN var_fecha_desde AND var_fecha_hasta
      AND ep.estado_pedido != 'Cancelado';
END $$

-- Productos mas vendidos de una sucursal
CREATE OR REPLACE PROCEDURE gestor_top_productos_sucursal(
    IN var_id_sucursal INT,
    IN var_fecha_desde DATE,
    IN var_fecha_hasta DATE,
    IN var_limit INT
)
BEGIN
    SELECT 
        pr.id_producto,
        s.sku AS SKU_Producto,
        m.nombre_producto AS Nombre_Modelo,
        SUM(pd.cantidad_producto) AS Unidades_Vendidas,
        SUM(pd.cantidad_producto * pr.precio_unitario) AS Ingreso_Total_Generado
    FROM Pedidos_Detalles pd
    JOIN Productos pr ON pd.id_producto = pr.id_producto
    JOIN Modelos m ON pr.id_modelo = m.id_modelo
    JOIN Sku s ON pr.id_sku = s.id_sku
    JOIN Pedidos pe ON pd.id_pedido = pe.id_pedido
    JOIN Estados_Pedidos ep ON pe.id_estado_pedido = ep.id_estado_pedido
    WHERE pd.id_sucursal = var_id_sucursal
      AND DATE(pe.fecha_pedido) BETWEEN var_fecha_desde AND var_fecha_hasta
      AND ep.estado_pedido != 'Cancelado'
    GROUP BY pr.id_producto, s.sku, m.nombre_producto
    ORDER BY Unidades_Vendidas DESC
    LIMIT var_limit;
END $$

DELIMITER $$
-- Inventario de una sucursal (productos con stock)
CREATE OR REPLACE PROCEDURE gestor_inventario_sucursal(
    IN var_id_sucursal INT
)
BEGIN
    SELECT 
        sp.id_sucursal_producto,
        sp.id_producto,
        m.nombre_producto,
        s.sku,
        c.nombre_categoria,
        sp.stock_actual,
        sp.stock_ideal,
        sp.stock_maximo,
        (sp.stock_ideal - sp.stock_actual) AS unidades_faltantes,
        pr.precio_unitario,
        pr.costo_unitario,
        (sp.stock_actual * pr.costo_unitario) AS valor_inventario,
        CASE 
            WHEN sp.stock_actual < sp.stock_ideal THEN 'Bajo'
            ELSE 'Normal'
        END AS estado_stock
    FROM Sucursales_Productos sp
    JOIN Productos pr ON sp.id_producto = pr.id_producto
    JOIN Modelos m ON pr.id_modelo = m.id_modelo
    JOIN Sku s ON pr.id_sku = s.id_sku
    JOIN Categorias c ON m.id_categoria = c.id_categoria
    WHERE sp.id_sucursal = var_id_sucursal
      AND pr.activo_producto = TRUE
    ORDER BY m.nombre_producto;
END $$

DELIMITER $$
-- Stock bajo de una sucursal
CREATE OR REPLACE PROCEDURE gestor_stock_bajo_sucursal(
    IN var_id_sucursal INT
)
BEGIN
    SELECT 
        sp.id_producto,
        m.nombre_producto,
        s.sku,
        sp.stock_actual,
        sp.stock_ideal,
        (sp.stock_ideal - sp.stock_actual) AS unidades_faltantes
    FROM Sucursales_Productos sp
    JOIN Productos pr ON sp.id_producto = pr.id_producto
    JOIN Modelos m ON pr.id_modelo = m.id_modelo
    JOIN Sku s ON pr.id_sku = s.id_sku
    WHERE sp.id_sucursal = var_id_sucursal
      AND sp.stock_actual < sp.stock_ideal
      AND pr.activo_producto = TRUE
    ORDER BY unidades_faltantes DESC;
END $$

DELIMITER $$
-- KPIs de inventario de una sucursal
CREATE OR REPLACE PROCEDURE gestor_kpis_inventario_sucursal(
    IN var_id_sucursal INT
)
BEGIN
    SELECT 
        COUNT(DISTINCT sp.id_producto) AS total_productos,
        COALESCE(SUM(sp.stock_actual), 0) AS total_piezas,
        COUNT(CASE WHEN sp.stock_actual < sp.stock_ideal THEN 1 END) AS productos_stock_bajo,
        COALESCE(SUM(sp.stock_actual * pr.costo_unitario), 0) AS valor_total_inventario
    FROM Sucursales_Productos sp
    JOIN Productos pr ON sp.id_producto = pr.id_producto
    WHERE sp.id_sucursal = var_id_sucursal
      AND pr.activo_producto = TRUE;
END $$

DELIMITER ;

DELIMITER ;
DELIMITER $$

-- =====================================================
-- 1) admin_devolucion_actualizar_estado
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_devolucion_actualizar_estado(
    IN p_id_devolucion INT,
    IN p_nuevo_estado VARCHAR(50),
    IN p_id_usuario_rol INT
)
BEGIN
    DECLARE v_id_estado_nuevo INT;
    DECLARE v_existe_devolucion BOOLEAN DEFAULT FALSE;
    DECLARE v_error_msg VARCHAR(255);

    -- Handler silencioso por si falta alguna tabla
    DECLARE CONTINUE HANDLER FOR SQLSTATE '42S02' BEGIN END;

    -- Validar que exista la devoluciÃ³n
    SELECT EXISTS(
        SELECT 1 FROM Devoluciones WHERE id_devolucion = p_id_devolucion
    )
    INTO v_existe_devolucion;

    IF NOT v_existe_devolucion THEN
        SET v_error_msg = 'Error: La devoluciÃ³n no existe.';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_msg;
    END IF;

    -- Buscar el ID del nuevo estado
    SELECT id_estado_devolucion INTO v_id_estado_nuevo
    FROM Estados_Devoluciones
    WHERE estado_devolucion = p_nuevo_estado
    LIMIT 1;

    IF v_id_estado_nuevo IS NULL THEN
        SET v_error_msg = CONCAT('Error: El estado "', p_nuevo_estado, '" no existe.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_msg;
    END IF;

    -- Actualizar estado en detalles
    UPDATE Devoluciones_Detalles
    SET id_estado_devolucion = v_id_estado_nuevo
    WHERE id_devolucion = p_id_devolucion;

    -- AuditorÃ­a
    INSERT INTO Auditoria_Devoluciones(
        id_devolucion,
        id_usuario_rol,
        accion_auditoria,
        fecha_auditoria,
        detalles_auditoria
    )
    VALUES(
        p_id_devolucion,
        p_id_usuario_rol,
        'Cambio de Estado',
        NOW(),
        CONCAT('Estado cambiado a: ', p_nuevo_estado)
    );

    SELECT CONCAT('Estado de la devoluciÃ³n actualizado exitosamente a: ', p_nuevo_estado) AS Mensaje;
END$$

-- =====================================================
-- 2) admin_devolucion_detalles
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_devolucion_detalles(
    IN p_id_devolucion INT
)
BEGIN
    -- Cabecera de la devoluciÃ³n
    SELECT
        d.id_devolucion,
        d.id_pedido,
        d.fecha_devolucion,
        p.fecha_pedido,
        COALESCE((
            SELECT SUM(pd.cantidad_producto * pr.precio_unitario)
            FROM Pedidos_Detalles pd
            JOIN Productos pr ON pd.id_producto = pr.id_producto
            WHERE pd.id_pedido = p.id_pedido
        ), 0) AS total_pedido,
        CONCAT(
            u.nombre_primero, ' ',
            IFNULL(u.nombre_segundo, ''), ' ',
            u.apellido_paterno, ' ',
            IFNULL(u.apellido_materno, '')
        ) AS nombre_cliente,
        u.correo AS email_cliente,
        COUNT(DISTINCT dd.id_devolucion_detalle) AS cantidad_productos_devueltos
    FROM Devoluciones d
    JOIN Pedidos p ON d.id_pedido = p.id_pedido
    JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    JOIN Clientes c ON pc.id_cliente = c.id_cliente
    JOIN Usuarios u ON c.id_usuario = u.id_usuario
    LEFT JOIN Devoluciones_Detalles dd ON d.id_devolucion = dd.id_devolucion
    WHERE d.id_devolucion = p_id_devolucion
    GROUP BY
        d.id_devolucion,
        d.id_pedido,
        d.fecha_devolucion,
        p.fecha_pedido,
        u.nombre_primero,
        u.nombre_segundo,
        u.apellido_paterno,
        u.apellido_materno,
        u.correo;

    -- Detalle de productos devueltos
    SELECT
        dd.id_devolucion_detalle,
        pd.id_producto,
        dd.cantidad_devuelta AS cantidad_devolucion,
        m.nombre_producto,
        s.sku,
        pr.precio_unitario,
        (dd.cantidad_devuelta * pr.precio_unitario) AS subtotal_devolucion,
        td.tipo_devolucion,
        dd.motivo_devolucion,
        ed.estado_devolucion,
        r.id_reembolso,
        r.monto_reembolso,
        r.fecha_reembolso,
        cr.tipo_reembolso AS clasificacion_reembolso
    FROM Devoluciones_Detalles dd
    JOIN Pedidos_Detalles pd ON dd.id_pedido_detalle = pd.id_pedido_detalle
    JOIN Productos pr ON pd.id_producto = pr.id_producto
    JOIN Modelos m ON pr.id_modelo = m.id_modelo
    JOIN Sku s ON pr.id_sku = s.id_sku
    JOIN Tipos_Devoluciones td ON dd.id_tipo_devoluciones = td.id_tipo_devoluciones
    JOIN Estados_Devoluciones ed ON dd.id_estado_devolucion = ed.id_estado_devolucion
    LEFT JOIN Reembolsos_Devolucion_Detalle rdd ON dd.id_devolucion_detalle = rdd.id_devolucion_detalle
    LEFT JOIN Reembolsos r ON rdd.id_reembolso = r.id_reembolso
    LEFT JOIN Clasificaciones_Reembolsos cr ON r.id_clasificacion_reembolso = cr.id_clasificacion_reembolso
    WHERE dd.id_devolucion = p_id_devolucion
    ORDER BY dd.id_devolucion_detalle;
END$$

-- =====================================================
-- 3) admin_empleado_crear
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_empleado_crear(
    IN p_nombre_usuario    VARCHAR(50),
    IN p_nombre_primero    VARCHAR(50),
    IN p_nombre_segundo    VARCHAR(50),
    IN p_apellido_paterno  VARCHAR(50),
    IN p_apellido_materno  VARCHAR(50),
    IN p_rfc_usuario       CHAR(13),
    IN p_telefono          VARCHAR(15),
    IN p_correo            VARCHAR(150),
    IN p_id_genero         INT,
    IN p_contrasena        VARCHAR(255),
    IN p_id_rol            INT,
    IN p_id_sucursal       INT
)
BEGIN
    DECLARE v_id_usuario_nuevo INT;
    DECLARE v_id_roles_sucursal INT;
    DECLARE v_id_usuario_rol_sucursal INT;

    -- Validar nombre de usuario
    IF EXISTS (SELECT 1 FROM Usuarios WHERE nombre_usuario = p_nombre_usuario) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: El nombre de usuario ya estÃ¡ en uso.';
    END IF;

    -- Validar RFC (si viene)
    IF p_rfc_usuario IS NOT NULL AND p_rfc_usuario <> '' THEN
        IF EXISTS (SELECT 1 FROM Usuarios WHERE rfc_usuario = p_rfc_usuario) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: El RFC ya estÃ¡ registrado.';
        END IF;
    END IF;

    -- Validar rol
    IF NOT EXISTS (SELECT 1 FROM Roles WHERE id_roles = p_id_rol) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: El rol especificado no existe.';
    END IF;

    -- Validar sucursal
    IF NOT EXISTS (
        SELECT 1
        FROM Sucursales
        WHERE id_sucursal = p_id_sucursal
          AND activo_sucursal = 1
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: La sucursal especificada no existe o estÃ¡ inactiva.';
    END IF;

    -- Crear usuario
    INSERT INTO Usuarios (
        nombre_usuario,
        nombre_primero,
        nombre_segundo,
        apellido_paterno,
        apellido_materno,
        rfc_usuario,
        telefono,
        correo,
        id_genero,
        contrasena,
        fecha_registro_usuario
    ) VALUES (
        p_nombre_usuario,
        p_nombre_primero,
        NULLIF(p_nombre_segundo, ''),
        p_apellido_paterno,
        NULLIF(p_apellido_materno, ''),
        NULLIF(p_rfc_usuario, ''),
        NULLIF(p_telefono, ''),
        NULLIF(p_correo, ''),
        p_id_genero,
        p_contrasena,
        NOW()
    );

    SET v_id_usuario_nuevo = LAST_INSERT_ID();

    -- Roles_Sucursales
    SELECT id_roles_sucursal INTO v_id_roles_sucursal
    FROM Roles_Sucursales
    WHERE id_roles = p_id_rol
      AND id_sucursal = p_id_sucursal
    LIMIT 1;

    IF v_id_roles_sucursal IS NULL THEN
        INSERT INTO Roles_Sucursales (id_roles, id_sucursal)
        VALUES (p_id_rol, p_id_sucursal);
        SET v_id_roles_sucursal = LAST_INSERT_ID();
    END IF;

    -- Usuarios_Roles_Sucursales
    INSERT INTO Usuarios_Roles_Sucursales (
        id_usuario,
        id_roles_sucursal,
        activo_usuario_rol_sucursal
    ) VALUES (
        v_id_usuario_nuevo,
        v_id_roles_sucursal,
        1
    );

    -- Usuarios_Roles
    INSERT INTO Usuarios_Roles (
        id_usuario,
        id_roles,
        id_usuario_rol_sucursal,
        fecha_asignacion,
        activo_usuario_rol
    ) VALUES (
        v_id_usuario_nuevo,
        p_id_rol,
        LAST_INSERT_ID(),
        CURDATE(),
        1
    );

    SELECT CONCAT('Empleado registrado exitosamente. ID Usuario: ', v_id_usuario_nuevo) AS Mensaje;
END$$

-- =====================================================
-- 4) admin_facturas_lista
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_facturas_lista(
    IN p_fecha_inicio DATETIME,
    IN p_fecha_fin    DATETIME,
    IN p_busqueda     VARCHAR(100)
)
BEGIN
    SELECT
        f.id_factura,
        f.folio,
        f.id_pedido,
        f.fecha_emision,
        f.subtotal,
        f.impuestos,
        f.total,
        COALESCE(ef.estado_factura, 'Emitida') AS estado_factura,
        COALESCE(
            CONCAT(
                IFNULL(u.nombre_primero, ''), ' ',
                IFNULL(u.nombre_segundo, ''), ' ',
                IFNULL(u.apellido_paterno, ''), ' ',
                IFNULL(u.apellido_materno, '')
            ),
            'N/A'
        ) AS nombre_cliente,
        u.nombre_usuario,
        COALESCE(SUM(mp.monto_metodo_pago), 0) AS total_pagado,
        (f.total - COALESCE(SUM(mp.monto_metodo_pago), 0)) AS pendiente,
        CASE
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total THEN 'Pagada'
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) > 0 THEN 'Parcial'
            ELSE 'Pendiente'
        END AS estado_pago,
        p.fecha_pedido
    FROM Facturas f
    INNER JOIN Pedidos p ON f.id_pedido = p.id_pedido
    LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
    LEFT JOIN Usuarios u ON c.id_usuario = u.id_usuario
    LEFT JOIN Estados_Facturas ef
        ON f.id_factura = ef.id_factura
       AND ef.fecha_estado_factura = (
            SELECT MAX(ef2.fecha_estado_factura)
            FROM Estados_Facturas ef2
            WHERE ef2.id_factura = f.id_factura
       )
    LEFT JOIN Pagos pa ON f.id_factura = pa.id_factura
    LEFT JOIN Montos_Pagos mp ON pa.id_pago = mp.id_pago
    WHERE
        (p_fecha_inicio IS NULL OR f.fecha_emision >= p_fecha_inicio)
        AND (p_fecha_fin IS NULL OR f.fecha_emision <= p_fecha_fin)
        AND (
            p_busqueda IS NULL
            OR p_busqueda = ''
            OR f.folio LIKE CONCAT('%', p_busqueda, '%')
            OR CAST(f.id_factura AS CHAR) LIKE CONCAT('%', p_busqueda, '%')
            OR CAST(f.id_pedido AS CHAR) LIKE CONCAT('%', p_busqueda, '%')
            OR CONCAT(IFNULL(u.nombre_primero,''), ' ', IFNULL(u.apellido_paterno,'')) LIKE CONCAT('%', p_busqueda, '%')
            OR u.nombre_usuario LIKE CONCAT('%', p_busqueda, '%')
        )
    GROUP BY
        f.id_factura,
        f.folio,
        f.id_pedido,
        f.fecha_emision,
        f.subtotal,
        f.impuestos,
        f.total,
        ef.estado_factura,
        u.nombre_primero,
        u.nombre_segundo,
        u.apellido_paterno,
        u.apellido_materno,
        u.nombre_usuario,
        p.fecha_pedido
    ORDER BY
        f.fecha_emision DESC,
        f.id_factura DESC
    LIMIT 500;
END$$

-- =====================================================
-- 5) admin_inventario_productos
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_inventario_productos()
BEGIN
    SELECT
        p.id_producto,
        p.precio_unitario,
        p.costo_unitario,
        p.activo_producto,
        m.nombre_producto,
        m.nombre_producto AS nombre,
        s.sku,
        c.nombre_categoria,
        mat.material,
        gp.genero_producto,
        sp.id_sucursal,
        su.nombre_sucursal,
        sp.stock_actual,
        sp.stock_ideal,
        GREATEST(sp.stock_ideal - sp.stock_actual, 0) AS unidades_faltantes,
        GREATEST(sp.stock_ideal - sp.stock_actual, 0) AS Unidades_Faltantes
    FROM Productos p
    INNER JOIN Modelos m              ON p.id_modelo   = m.id_modelo
    INNER JOIN Categorias c           ON m.id_categoria = c.id_categoria
    INNER JOIN Sku s                  ON p.id_sku      = s.id_sku
    INNER JOIN Materiales mat         ON p.id_material = mat.id_material
    INNER JOIN Generos_Productos gp   ON m.id_genero_producto = gp.id_genero_producto
    INNER JOIN Sucursales_Productos sp ON p.id_producto = sp.id_producto
    INNER JOIN Sucursales su          ON su.id_sucursal = sp.id_sucursal
    ORDER BY
        su.nombre_sucursal,
        m.nombre_producto,
        s.sku;
END$$

-- =====================================================
-- 6) admin_kpi_pedidos_totales
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_kpi_pedidos_totales()
BEGIN
    SELECT COALESCE(SUM(Total_Pedidos), 0) AS total_pedidos
    FROM vPedidosPorEstado
    WHERE estado_pedido <> 'Cancelado';
END$$

-- =====================================================
-- 7) admin_kpi_productos_stock
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_kpi_productos_stock()
BEGIN
    SELECT
        (SELECT COUNT(*)
         FROM Productos
         WHERE activo_producto = 1) AS total_modelos_unicos,
        (SELECT COALESCE(SUM(stock_actual), 0)
         FROM Sucursales_Productos) AS total_piezas_fisicas,
        (SELECT COALESCE(SUM(sp.stock_actual * p.costo_unitario), 0)
         FROM Sucursales_Productos sp
         JOIN Productos p ON sp.id_producto = p.id_producto) AS valor_total_inventario;
END$$

-- =====================================================
-- 8) admin_kpi_ventas_totales
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_kpi_ventas_totales(
    IN p_fecha_desde DATE,
    IN p_fecha_hasta DATE
)
BEGIN
    SELECT COALESCE(SUM(Total_Facturado_Diario), 0) AS total_ventas
    FROM vFacturacionDiaria
    WHERE Dia >= p_fecha_desde
      AND Dia <= p_fecha_hasta;
END$$

-- =====================================================
-- 9) admin_pedidos_filtrados
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_pedidos_filtrados(
    IN p_fecha_filtro DATE,
    IN p_orden        VARCHAR(4)   -- 'ASC' o 'DESC'
)
BEGIN
    SELECT DISTINCT
        p.id_pedido,
        DATE_FORMAT(p.fecha_pedido, '%Y-%m-%d %H:%i') AS fecha_formateada,
        p.fecha_pedido,
        ep.estado_pedido
    FROM Pedidos p
    JOIN Pedidos_Detalles pd ON p.id_pedido = pd.id_pedido
    JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    WHERE
        (p_fecha_filtro IS NULL OR DATE(p.fecha_pedido) = p_fecha_filtro)
    ORDER BY
        CASE WHEN p_orden = 'ASC' THEN p.fecha_pedido END ASC,
        CASE WHEN p_orden = 'DESC' THEN p.fecha_pedido END DESC
    LIMIT 50;
END$$
DELIMITER $$
-- =====================================================
-- 10) admin_producto_detalles
-- =====================================================
CREATE OR REPLACE PROCEDURE admin_producto_detalles(
    IN p_id_producto INT
)
BEGIN
    -- Datos del producto
    SELECT
        p.id_producto,
        p.precio_unitario,
        p.descuento_producto,
        p.costo_unitario,
        p.activo_producto,
        m.nombre_producto,
        m.id_modelo,
        c.nombre_categoria,
        c.id_categoria,
        s.sku,
        mat.material,
        mat.id_material,
        gp.genero_producto,
        gp.id_genero_producto,
        tp.talla,
        pok.kilataje,
        ppl.ley
    FROM Productos p
    JOIN Modelos m ON p.id_modelo = m.id_modelo
    JOIN Categorias c ON m.id_categoria = c.id_categoria
    JOIN Sku s ON p.id_sku = s.id_sku
    JOIN Materiales mat ON p.id_material = mat.id_material
    JOIN Generos_Productos gp ON m.id_genero_producto = gp.id_genero_producto
    LEFT JOIN Tallas_Productos tp ON p.id_producto = tp.id_producto
    LEFT JOIN Productos_Oro_Kilataje pok ON p.id_producto = pok.id_producto
    LEFT JOIN Productos_Plata_Ley ppl ON p.id_producto = ppl.id_producto
    WHERE p.id_producto = p_id_producto;

    -- Stock por sucursal
    SELECT
        s.id_sucursal,
        s.nombre_sucursal,
        sp.stock_actual,
        sp.stock_ideal
    FROM Sucursales_Productos sp
    JOIN Sucursales s ON sp.id_sucursal = s.id_sucursal
    WHERE sp.id_producto = p_id_producto
    ORDER BY s.nombre_sucursal;
END$$
DELIMITER ;
-- =====================================================
-- 11) admin_sucursales_lista
-- =====================================================
DELIMITER $$
CREATE OR REPLACE PROCEDURE admin_sucursales_lista()
BEGIN
    SELECT
        s.id_sucursal,
        s.nombre_sucursal,
        s.activo_sucursal,
        d.calle_direccion,
        d.numero_direccion,
        cp.codigo_postal,
        e.estado_direccion,
        m.municipio_direccion,
        COALESCE(COUNT(DISTINCT urs.id_usuario), 0) AS cantidad_usuarios
    FROM Sucursales s
    JOIN Direcciones d ON s.id_direccion = d.id_direccion
    JOIN Codigos_Postales cp ON d.id_cp = cp.id_cp
    LEFT JOIN Codigos_Postales_Estados cpe ON cp.id_cp = cpe.id_cp
    LEFT JOIN Estados_Direcciones e ON cpe.id_estado_direccion = e.id_estado_direccion
    LEFT JOIN Codigos_Postales_Municipios cpm ON cp.id_cp = cpm.id_cp
    LEFT JOIN Municipios_Direcciones m ON cpm.id_municipio_direccion = m.id_municipio_direccion
    LEFT JOIN Roles_Sucursales rs ON s.id_sucursal = rs.id_sucursal
    LEFT JOIN Usuarios_Roles_Sucursales urs
        ON rs.id_roles_sucursal = urs.id_roles_sucursal
       AND urs.activo_usuario_rol_sucursal = 1
    GROUP BY
        s.id_sucursal,
        s.nombre_sucursal,
        s.activo_sucursal,
        d.calle_direccion,
        d.numero_direccion,
        cp.codigo_postal,
        e.estado_direccion,
        m.municipio_direccion
    ORDER BY s.id_sucursal;
END$$

DELIMITER ;
DELIMITER $$

-- =========================================
-- categoriasActivas
-- =========================================
CREATE OR REPLACE PROCEDURE categoriasActivas()
BEGIN
    SELECT id_categoria, nombre_categoria
    FROM Categorias
    WHERE activo_categoria = 1
    ORDER BY nombre_categoria;
END$$

-- =========================================
-- clienteActualizarDatos
-- =========================================
CREATE OR REPLACE PROCEDURE clienteActualizarDatos(
    IN p_id_usuario   INT,
    IN p_rfc          VARCHAR(13),
    IN p_cp           VARCHAR(10),
    IN p_id_estado    INT,
    IN p_id_municipio INT,
    IN p_calle        VARCHAR(150),
    IN p_numero       VARCHAR(20),
    IN p_telefono     VARCHAR(20)
)
BEGIN
    DECLARE v_id_cp INT;
    DECLARE v_id_direccion INT;

    IF p_rfc IS NOT NULL THEN
        UPDATE Usuarios
        SET rfc_usuario = p_rfc
        WHERE id_usuario = p_id_usuario;
    END IF;

    IF p_cp IS NOT NULL THEN
        SELECT id_cp INTO v_id_cp
        FROM Codigos_Postales
        WHERE codigo_postal = p_cp
        LIMIT 1;

        IF v_id_cp IS NULL THEN
            INSERT INTO Codigos_Postales(codigo_postal) VALUES (p_cp);
            SET v_id_cp = LAST_INSERT_ID();
        END IF;

        IF p_id_estado IS NOT NULL THEN
            INSERT IGNORE INTO Codigos_Postales_Estados(id_cp, id_estado_direccion)
            VALUES (v_id_cp, p_id_estado);
        END IF;

        IF p_id_municipio IS NOT NULL THEN
            INSERT IGNORE INTO Codigos_Postales_Municipios(id_cp, id_municipio_direccion)
            VALUES (v_id_cp, p_id_municipio);
        END IF;
    END IF;

    IF p_calle IS NOT NULL AND p_numero IS NOT NULL AND v_id_cp IS NOT NULL THEN
        SELECT id_direccion INTO v_id_direccion
        FROM Direcciones
        WHERE calle_direccion = p_calle
          AND numero_direccion = p_numero
          AND id_cp = v_id_cp
        LIMIT 1;

        IF v_id_direccion IS NULL THEN
            INSERT INTO Direcciones(calle_direccion, numero_direccion, id_cp)
            VALUES (p_calle, p_numero, v_id_cp);
            SET v_id_direccion = LAST_INSERT_ID();
        END IF;

        UPDATE Usuarios
        SET id_direccion = v_id_direccion
        WHERE id_usuario = p_id_usuario;
    END IF;

    IF p_telefono IS NOT NULL THEN
        UPDATE Usuarios
        SET telefono = p_telefono
        WHERE id_usuario = p_id_usuario;
    END IF;
END$$

-- =========================================
-- clienteCrear
-- =========================================

DELIMITER //

CREATE OR REPLACE PROCEDURE clienteCrear(
    -- Datos del Usuario
    IN p_nombre_usuario   VARCHAR(50),
    IN p_nombre_primero   VARCHAR(50),
    IN p_nombre_segundo   VARCHAR(50),   -- OPCIONAL (puede venir NULL o '')
    IN p_apellido_paterno VARCHAR(50),
    IN p_apellido_materno VARCHAR(50),
    IN p_rfc_usuario      CHAR(13),      -- OPCIONAL
    IN p_telefono         VARCHAR(15),
    IN p_correo           VARCHAR(150),
    IN p_contrasena       VARCHAR(255),
    IN p_nombre_genero    VARCHAR(200),  -- OPCIONAL

    -- Datos de Dirección (TODOS OPCIONALES)
    IN p_calle_direccion  VARCHAR(200),
    IN p_numero_direccion VARCHAR(10),
    IN p_codigo_postal    CHAR(5),

    -- Datos del Cliente
    IN p_id_clasificacion INT           -- Puede ser NULL si es cliente estándar
)
BEGIN
    DECLARE v_id_cp        INT;
    DECLARE v_id_direccion INT;
    DECLARE v_id_genero    INT DEFAULT NULL;
    DECLARE v_id_usuario   INT;
    DECLARE v_id_cliente   INT;
    DECLARE v_id_rol_cliente INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- ======================================================
    -- 1. GESTIÓN DEL CÓDIGO POSTAL (SOLO SI LO MANDAN)
    -- ======================================================
    SET v_id_cp = NULL;

    IF p_codigo_postal IS NOT NULL AND p_codigo_postal <> '' THEN
        SELECT id_cp
        INTO v_id_cp
        FROM Codigos_Postales
        WHERE codigo_postal = p_codigo_postal
        LIMIT 1;

        IF v_id_cp IS NULL THEN
            INSERT INTO Codigos_Postales (codigo_postal)
            VALUES (p_codigo_postal);

            SET v_id_cp = LAST_INSERT_ID();
        END IF;
    END IF;

    -- ======================================================
    -- 2. GESTIÓN DE LA DIRECCIÓN (SOLO SI HAY DATOS)
    -- ======================================================
    SET v_id_direccion = NULL;

    IF p_calle_direccion IS NOT NULL AND p_calle_direccion <> ''
    AND p_numero_direccion IS NOT NULL AND p_numero_direccion <> ''
    AND v_id_cp IS NOT NULL THEN

        INSERT INTO Direcciones (calle_direccion, numero_direccion, id_cp)
        VALUES (p_calle_direccion, p_numero_direccion, v_id_cp);

        SET v_id_direccion = LAST_INSERT_ID();
    END IF;

    -- ======================================================
    -- 3. GESTIÓN DEL GÉNERO (OPCIONAL)
    -- ======================================================
    SET v_id_genero = NULL;

    IF p_nombre_genero IS NOT NULL AND p_nombre_genero <> '' THEN
        SELECT id_genero
        INTO v_id_genero
        FROM Generos
        WHERE genero = p_nombre_genero
        LIMIT 1;
        -- Si no existe, simplemente se queda NULL
    END IF;

    -- ======================================================
    -- 4. CREACIÓN DEL USUARIO
    --    (RFC, segundo nombre y dirección pueden ser NULL)
    -- ======================================================
    INSERT INTO Usuarios (
        nombre_usuario,
        nombre_primero,
        nombre_segundo,
        apellido_paterno,
        apellido_materno,
        rfc_usuario,
        telefono,
        correo,
        id_genero,
        id_direccion,
        contrasena,
        fecha_registro_usuario
    ) VALUES (
        p_nombre_usuario,
        p_nombre_primero,
        NULLIF(p_nombre_segundo, ''),  -- convierte '' en NULL
        p_apellido_paterno,
        p_apellido_materno,
        NULLIF(p_rfc_usuario, ''),     -- convierte '' en NULL
        p_telefono,
        p_correo,
        v_id_genero,
        v_id_direccion,
        p_contrasena,
        NOW()
    );

    SET v_id_usuario = LAST_INSERT_ID();

    -- ======================================================
    -- 5. CREACIÓN DEL CLIENTE
    -- ======================================================
    INSERT INTO Clientes (
        id_clasificacion,
        id_usuario
    ) VALUES (
        p_id_clasificacion,   -- puede ser NULL
        v_id_usuario
    );

    SET v_id_cliente = LAST_INSERT_ID();

    -- ======================================================
    -- 6. ASIGNAR ROL DE CLIENTE AL USUARIO
    -- ======================================================
    -- Obtener el ID del rol "Cliente" (normalmente es 6)
    SET v_id_rol_cliente = NULL;
    
    SELECT id_roles INTO v_id_rol_cliente
    FROM Roles
    WHERE nombre_rol = 'Cliente'
    LIMIT 1;
    
    -- Si existe el rol Cliente, asignarlo al usuario
    IF v_id_rol_cliente IS NOT NULL THEN
        INSERT INTO Usuarios_Roles (
            id_usuario,
            id_roles,
            id_usuario_rol_sucursal,
            activo_usuario_rol,
            fecha_asignacion
        ) VALUES (
            v_id_usuario,
            v_id_rol_cliente,
            NULL,  -- Los clientes no tienen sucursal asignada
            1,     -- Activo
            CURDATE()
        );
    END IF;

    COMMIT;

    -- Regresamos el id del cliente creado
    SELECT v_id_cliente AS id_nuevo_cliente;
END //

DELIMITER $$

-- =========================================
-- cliente_contrasena_actualizar
-- =========================================
CREATE OR REPLACE PROCEDURE cliente_contrasena_actualizar(
    IN p_id_usuario        INT,
    IN p_contrasena_nueva  VARCHAR(500)
)
BEGIN
    DECLARE v_hash_actual VARCHAR(500);

    SELECT contrasena INTO v_hash_actual
    FROM Usuarios
    WHERE id_usuario = p_id_usuario;

    IF v_hash_actual IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Usuario no encontrado';
    END IF;

    UPDATE Usuarios
    SET contrasena = p_contrasena_nueva
    WHERE id_usuario = p_id_usuario;

    SELECT 'ContraseÃ±a actualizada exitosamente' AS mensaje;
END$$

-- =========================================
-- cliente_devoluciones_lista
-- =========================================
CREATE OR REPLACE PROCEDURE cliente_devoluciones_lista(
    IN p_id_usuario INT
)
BEGIN
    SELECT
        d.id_devolucion,
        d.id_pedido,
        d.fecha_devolucion,
        MIN(ed.estado_devolucion) AS estado_devolucion,
        MIN(td.tipo_devolucion) AS tipo_devolucion,
        COUNT(DISTINCT dd.id_devolucion_detalle) AS cantidad_productos,
        COALESCE(SUM(dd.cantidad_devuelta * pr.precio_unitario), 0) AS total_devolucion
    FROM Devoluciones d
    JOIN Pedidos p ON d.id_pedido = p.id_pedido
    JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    JOIN Clientes c ON pc.id_cliente = c.id_cliente
    LEFT JOIN Devoluciones_Detalles dd ON d.id_devolucion = dd.id_devolucion
    LEFT JOIN Pedidos_Detalles pd ON dd.id_pedido_detalle = pd.id_pedido_detalle
    LEFT JOIN Productos pr ON pd.id_producto = pr.id_producto
    LEFT JOIN Estados_Devoluciones ed ON dd.id_estado_devolucion = ed.id_estado_devolucion
    LEFT JOIN Tipos_Devoluciones td ON dd.id_tipo_devoluciones = td.id_tipo_devoluciones
    WHERE c.id_usuario = p_id_usuario
    GROUP BY d.id_devolucion, d.id_pedido, d.fecha_devolucion
    ORDER BY d.fecha_devolucion DESC, d.id_devolucion DESC
    LIMIT 100;
END$$

-- =========================================
-- cliente_facturas_lista
-- =========================================
CREATE OR REPLACE PROCEDURE cliente_facturas_lista(
    IN p_id_usuario INT
)
BEGIN
    SELECT
        f.id_factura,
        f.folio,
        f.id_pedido,
        f.fecha_emision,
        f.subtotal,
        f.impuestos,
        f.total,
        COALESCE(ef.estado_factura, 'Emitida') AS estado_factura,
        COALESCE(SUM(mp.monto_metodo_pago), 0) AS total_pagado,
        (f.total - COALESCE(SUM(mp.monto_metodo_pago), 0)) AS pendiente,
        CASE
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total THEN 'Pagada'
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) > 0 THEN 'Parcial'
            ELSE 'Pendiente'
        END AS estado_pago,
        p.fecha_pedido
    FROM Facturas f
    INNER JOIN Pedidos p ON f.id_pedido = p.id_pedido
    LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
    LEFT JOIN Estados_Facturas ef ON f.id_factura = ef.id_factura
        AND ef.fecha_estado_factura = (
            SELECT MAX(ef2.fecha_estado_factura)
            FROM Estados_Facturas ef2
            WHERE ef2.id_factura = f.id_factura
        )
    LEFT JOIN Pagos pa ON f.id_factura = pa.id_factura
    LEFT JOIN Montos_Pagos mp ON pa.id_pago = mp.id_pago
    WHERE c.id_usuario = p_id_usuario
    GROUP BY
        f.id_factura,
        f.folio,
        f.id_pedido,
        f.fecha_emision,
        f.subtotal,
        f.impuestos,
        f.total,
        ef.estado_factura,
        p.fecha_pedido
    ORDER BY f.fecha_emision DESC, f.id_factura DESC
    LIMIT 100;
END$$

-- =========================================
-- cliente_pago_registrar
-- =========================================
CREATE OR REPLACE PROCEDURE cliente_pago_registrar(
    IN p_id_usuario      INT,
    IN p_id_factura      INT,
    IN p_id_metodo_pago  INT,
    IN p_importe         DECIMAL(10,2)
)
BEGIN
    DECLARE v_total_factura DECIMAL(10,2);
    DECLARE v_total_pagado DECIMAL(10,2);
    DECLARE v_pendiente DECIMAL(10,2);
    DECLARE v_id_pago_nuevo INT;
    DECLARE v_nuevo_estado VARCHAR(50);
    DECLARE v_factura_existe INT;
    DECLARE v_factura_pertenece_cliente INT;
    DECLARE v_mensaje_error VARCHAR(255);
    DECLARE v_id_pedido INT;

    -- Validar existencia de factura
    SELECT COUNT(*) INTO v_factura_existe
    FROM Facturas
    WHERE id_factura = p_id_factura;

    IF v_factura_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La factura no existe.';
    END IF;

    -- Validar que la factura pertenezca al cliente
    SELECT COUNT(*) INTO v_factura_pertenece_cliente
    FROM Facturas f
    JOIN Pedidos p ON f.id_pedido = p.id_pedido
    JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    JOIN Clientes c ON pc.id_cliente = c.id_cliente
    WHERE f.id_factura = p_id_factura
      AND c.id_usuario = p_id_usuario;

    IF v_factura_pertenece_cliente = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La factura no pertenece al cliente.';
    END IF;

    -- Datos de factura
    SELECT total, id_pedido INTO v_total_factura, v_id_pedido
    FROM Facturas
    WHERE id_factura = p_id_factura;

    -- Total pagado actual
    SELECT COALESCE(SUM(mp.monto_metodo_pago), 0) INTO v_total_pagado
    FROM Pagos pa
    JOIN Montos_Pagos mp ON pa.id_pago = mp.id_pago
    WHERE pa.id_factura = p_id_factura;

    SET v_pendiente = v_total_factura - v_total_pagado;

    -- Validaciones del importe
    IF p_importe > v_pendiente THEN
        SET v_mensaje_error = CONCAT(
            'El importe no puede ser mayor al pendiente (',
            FORMAT(v_pendiente, 2),
            ').'
        );
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_mensaje_error;
    END IF;

    IF p_importe <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El importe debe ser mayor a cero.';
    END IF;

    -- Crear pago
    INSERT INTO Pagos (id_factura, id_pedido, fecha_pago)
    VALUES (p_id_factura, v_id_pedido, CURDATE());

    SET v_id_pago_nuevo = LAST_INSERT_ID();

    -- Monto del pago
    INSERT INTO Montos_Pagos (id_metodo_pago, id_pago, monto_metodo_pago)
    VALUES (p_id_metodo_pago, v_id_pago_nuevo, p_importe);

    SET v_total_pagado = v_total_pagado + p_importe;

    -- Estado de factura
    IF v_total_pagado >= v_total_factura THEN
        SET v_nuevo_estado = 'Pagada';
    ELSE
        SET v_nuevo_estado = 'Parcial';
    END IF;

    -- Reset estados anteriores
    DELETE FROM Estados_Facturas
    WHERE id_factura = p_id_factura;

    -- Insertar nuevo estado
    INSERT INTO Estados_Facturas (id_factura, estado_factura, fecha_estado_factura)
    VALUES (p_id_factura, v_nuevo_estado, CURDATE());

    SELECT
        'Pago registrado exitosamente' AS Mensaje,
        v_nuevo_estado AS Estado,
        v_total_pagado AS Total_Pagado,
        (v_total_factura - v_total_pagado) AS Pendiente;
END$$

-- =========================================
-- cliente_pedidos_disponibles_devolucion
-- =========================================
CREATE OR REPLACE PROCEDURE cliente_pedidos_disponibles_devolucion(
    IN p_id_usuario INT
)
BEGIN
    SELECT DISTINCT
        p.id_pedido,
        p.fecha_pedido,
        ep.estado_pedido,
        COALESCE((
            SELECT SUM(pd.cantidad_producto * pr.precio_unitario)
            FROM Pedidos_Detalles pd
            JOIN Productos pr ON pd.id_producto = pr.id_producto
            WHERE pd.id_pedido = p.id_pedido
        ), 0) AS total_pedido
    FROM Pedidos p
    LEFT JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
    WHERE c.id_usuario = p_id_usuario
      AND ep.estado_pedido IN ('Completado', 'Procesado', 'Confirmado')
      AND EXISTS (
          SELECT 1
          FROM Pedidos_Detalles pd
          LEFT JOIN Devoluciones_Detalles dd
              ON pd.id_pedido_detalle = dd.id_pedido_detalle
          WHERE pd.id_pedido = p.id_pedido
            AND (
                dd.id_devolucion_detalle IS NULL
                OR dd.cantidad_devuelta < pd.cantidad_producto
            )
      )
    ORDER BY p.fecha_pedido DESC
    LIMIT 50;
END$$

-- =========================================
-- cliente_pedidos_lista
-- =========================================
CREATE OR REPLACE PROCEDURE cliente_pedidos_lista(
    IN p_id_usuario INT
)
BEGIN
    SELECT
        p.id_pedido,
        p.fecha_pedido,
        COALESCE((
            SELECT SUM(pd.cantidad_producto * pr.precio_unitario)
            FROM Pedidos_Detalles pd
            JOIN Productos pr ON pd.id_producto = pr.id_producto
            WHERE pd.id_pedido = p.id_pedido
        ), 0) AS total_pedido,
        ep.estado_pedido,
        ep.id_estado_pedido,
        f.id_factura,
        f.folio,
        f.total AS total_factura
    FROM Pedidos p
    LEFT JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
    LEFT JOIN Facturas f ON p.id_pedido = f.id_pedido
    WHERE c.id_usuario = p_id_usuario
    ORDER BY p.fecha_pedido DESC
    LIMIT 100;
END$$

-- =========================================
-- cliente_pedido_detalles
-- =========================================
CREATE OR REPLACE PROCEDURE cliente_pedido_detalles(
    IN p_id_pedido  INT,
    IN p_id_usuario INT
)
BEGIN
    -- Validar que el pedido pertenece al usuario
    IF NOT EXISTS (
        SELECT 1
        FROM Pedidos p
        JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
        JOIN Clientes c ON pc.id_cliente = c.id_cliente
        WHERE p.id_pedido = p_id_pedido
          AND c.id_usuario = p_id_usuario
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Pedido no encontrado o no pertenece al cliente';
    END IF;

    -- Detalles del pedido
    SELECT
        pd.id_pedido_detalle,
        pd.id_producto,
        pd.cantidad_producto,
        m.nombre_producto,
        p.precio_unitario,
        s.sku,
        (pd.cantidad_producto * p.precio_unitario) AS subtotal,
        COALESCE(SUM(dd.cantidad_devuelta), 0) AS cantidad_devuelta,
        (pd.cantidad_producto - COALESCE(SUM(dd.cantidad_devuelta), 0)) AS cantidad_disponible_devolucion
    FROM Pedidos_Detalles pd
    JOIN Productos pr ON pd.id_producto = pr.id_producto
    JOIN Modelos m ON pr.id_modelo = m.id_modelo
    JOIN Sku s ON pr.id_sku = s.id_sku
    JOIN Productos p ON pd.id_producto = p.id_producto
    LEFT JOIN Devoluciones_Detalles dd ON pd.id_pedido_detalle = dd.id_pedido_detalle
    WHERE pd.id_pedido = p_id_pedido
    GROUP BY
        pd.id_pedido_detalle,
        pd.id_producto,
        pd.cantidad_producto,
        m.nombre_producto,
        p.precio_unitario,
        s.sku
    ORDER BY m.nombre_producto;
END$$

DELIMITER ;


DELIMITER $$

-- =========================================
DELIMITER $$

-- =========================================
-- cliente_perfil_actualizar
-- =========================================
CREATE OR REPLACE PROCEDURE cliente_perfil_actualizar(
    IN var_id_usuario          INT,
    IN var_nombre_usuario      VARCHAR(50),
    IN var_nombre_primero      VARCHAR(50),
    IN var_nombre_segundo      VARCHAR(50),
    IN var_apellido_paterno    VARCHAR(50),
    IN var_apellido_materno    VARCHAR(50),
    IN var_rfc_usuario         VARCHAR(13),
    IN var_telefono            VARCHAR(20),
    IN var_correo              VARCHAR(150),
    IN var_id_genero           INT,
    IN var_codigo_postal       VARCHAR(10),
    IN var_municipio           VARCHAR(100),
    IN var_id_estado_direccion INT,
    IN var_calle_direccion     VARCHAR(150),
    IN var_numero_direccion    VARCHAR(20)
)
BEGIN
    DECLARE var_id_direccion     INT;
    DECLARE var_id_cp            INT;
    DECLARE var_id_municipio     INT;
    DECLARE var_id_cp_municipio  INT;
    DECLARE var_id_cp_estado     INT;
    
    -- Actualizar datos bÃ¡sicos del usuario
    UPDATE Usuarios
    SET
        nombre_usuario   = var_nombre_usuario,
        nombre_primero   = var_nombre_primero,
        nombre_segundo   = IFNULL(var_nombre_segundo, ''),
        apellido_paterno = var_apellido_paterno,
        apellido_materno = IFNULL(var_apellido_materno, ''),
        rfc_usuario      = IFNULL(var_rfc_usuario, ''),
        telefono         = IFNULL(var_telefono, ''),
        correo           = IFNULL(var_correo, ''),
        id_genero        = var_id_genero
    WHERE id_usuario = var_id_usuario;

    -- CP
    SELECT id_cp INTO var_id_cp
    FROM Codigos_Postales
    WHERE codigo_postal = var_codigo_postal
    LIMIT 1;

    IF var_id_cp IS NULL THEN
        INSERT INTO Codigos_Postales (codigo_postal)
        VALUES (var_codigo_postal);
        SET var_id_cp = LAST_INSERT_ID();
    END IF;

    -- Municipio y relaciÃ³n CP-Municipio
    IF var_municipio IS NOT NULL AND var_municipio <> '' THEN
        SELECT id_municipio_direccion INTO var_id_municipio
        FROM Municipios_Direcciones
        WHERE municipio_direccion = var_municipio
        LIMIT 1;

        IF var_id_municipio IS NULL THEN
            INSERT INTO Municipios_Direcciones (municipio_direccion)
            VALUES (var_municipio);
            SET var_id_municipio = LAST_INSERT_ID();
        END IF;

        SELECT id_cp_municipio INTO var_id_cp_municipio
        FROM Codigos_Postales_Municipios
        WHERE id_cp = var_id_cp
          AND id_municipio_direccion = var_id_municipio
        LIMIT 1;

        IF var_id_cp_municipio IS NULL THEN
            INSERT INTO Codigos_Postales_Municipios (id_cp, id_municipio_direccion)
            VALUES (var_id_cp, var_id_municipio);
        END IF;
    END IF;

    -- Estado y relaciÃ³n CP-Estado
    IF var_id_estado_direccion IS NOT NULL THEN
        SELECT id_cp_estado INTO var_id_cp_estado
        FROM Codigos_Postales_Estados
        WHERE id_cp = var_id_cp
          AND id_estado_direccion = var_id_estado_direccion
        LIMIT 1;

        IF var_id_cp_estado IS NULL THEN
            INSERT INTO Codigos_Postales_Estados (id_cp, id_estado_direccion)
            VALUES (var_id_cp, var_id_estado_direccion);
        END IF;
    END IF;

    -- DirecciÃ³n del usuario
    SELECT id_direccion INTO var_id_direccion
    FROM Usuarios
    WHERE id_usuario = var_id_usuario;

    IF var_id_direccion IS NULL THEN
        -- Crear nueva direcciÃ³n
        INSERT INTO Direcciones (calle_direccion, numero_direccion, id_cp)
        VALUES (var_calle_direccion, var_numero_direccion, var_id_cp);
        SET var_id_direccion = LAST_INSERT_ID();

        UPDATE Usuarios
        SET id_direccion = var_id_direccion
        WHERE id_usuario = var_id_usuario;
    ELSE
        -- Actualizar direcciÃ³n existente
        UPDATE Direcciones
        SET
            calle_direccion  = var_calle_direccion,
            numero_direccion = var_numero_direccion,
            id_cp            = var_id_cp
        WHERE id_direccion = var_id_direccion;
    END IF;

    SELECT 'Perfil actualizado exitosamente' AS mensaje;
END$$

-- =========================================
-- cliente_perfil_obtener
-- =========================================
CREATE OR REPLACE PROCEDURE cliente_perfil_obtener(
    IN var_id_usuario INT
)
BEGIN
    SELECT
        u.id_usuario,
        u.nombre_usuario,
        u.nombre_primero,
        u.nombre_segundo,
        u.apellido_paterno,
        u.apellido_materno,
        u.rfc_usuario,
        u.telefono,
        u.correo,
        u.id_genero,
        g.genero,
        d.id_direccion,
        d.calle_direccion,
        d.numero_direccion,
        cp.codigo_postal,
        md.municipio_direccion,
        ed.id_estado_direccion,
        ed.estado_direccion,
        cl.id_clasificacion,
        cl.nombre_clasificacion,
        cl.descuento_clasificacion
    FROM Usuarios u
    LEFT JOIN Generos g ON u.id_genero = g.id_genero
    LEFT JOIN Clientes c ON u.id_usuario = c.id_usuario
    LEFT JOIN Clasificaciones cl ON c.id_clasificacion = cl.id_clasificacion
    LEFT JOIN Direcciones d ON u.id_direccion = d.id_direccion
    LEFT JOIN Codigos_Postales cp ON d.id_cp = cp.id_cp
    LEFT JOIN Codigos_Postales_Municipios cpm ON cp.id_cp = cpm.id_cp
    LEFT JOIN Municipios_Direcciones md ON cpm.id_municipio_direccion = md.id_municipio_direccion
    LEFT JOIN Codigos_Postales_Estados cpe ON cp.id_cp = cpe.id_cp
    LEFT JOIN Estados_Direcciones ed ON cpe.id_estado_direccion = ed.id_estado_direccion
    WHERE u.id_usuario = var_id_usuario;
END$$

-- =========================================
-- devolucionCrear
-- =========================================
CREATE OR REPLACE PROCEDURE devolucionCrear(
    IN p_id_pedido   INT,
    IN p_items_json  JSON
)
BEGIN
    DECLARE v_id_devolucion       INT;
    DECLARE v_id_estado_pendiente INT;

    DECLARE v_total_items INT;
    DECLARE v_index       INT DEFAULT 0;

    DECLARE v_id_producto        INT;
    DECLARE v_cantidad           INT;
    DECLARE v_motivo             VARCHAR(200);
    DECLARE v_id_tipo            INT;
    DECLARE v_id_pedido_detalle  INT;
    DECLARE v_cantidad_comprada  INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Validar pedido
    IF p_id_pedido IS NULL OR p_id_pedido <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: El ID del pedido es requerido y debe ser vÃ¡lido.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM Pedidos WHERE id_pedido = p_id_pedido) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: El pedido especificado no existe.';
    END IF;

    -- Estado "Pendiente"
    SELECT id_estado_devolucion INTO v_id_estado_pendiente
    FROM Estados_Devoluciones
    WHERE estado_devolucion = 'Pendiente'
    LIMIT 1;

    IF v_id_estado_pendiente IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No existe el estado de devoluciÃ³n "Pendiente".';
    END IF;

    -- Crear devoluciÃ³n
    INSERT INTO Devoluciones (id_pedido, fecha_devolucion)
    VALUES (p_id_pedido, CURDATE());

    SET v_id_devolucion = LAST_INSERT_ID();

    -- Iterar items JSON
    SET v_total_items = JSON_LENGTH(p_items_json);

    WHILE v_index < v_total_items DO

        SET v_id_producto = JSON_EXTRACT(p_items_json, CONCAT('$[', v_index, '].id_producto'));
        SET v_cantidad    = JSON_EXTRACT(p_items_json, CONCAT('$[', v_index, '].cantidad'));
        SET v_motivo      = JSON_UNQUOTE(JSON_EXTRACT(p_items_json, CONCAT('$[', v_index, '].motivo')));
        SET v_id_tipo     = JSON_EXTRACT(p_items_json, CONCAT('$[', v_index, '].id_tipo_devolucion'));

        -- Validar que el producto pertenezca al pedido
        SET v_id_pedido_detalle = NULL;

        SELECT id_pedido_detalle, cantidad_producto
        INTO v_id_pedido_detalle, v_cantidad_comprada
        FROM Pedidos_Detalles
        WHERE id_pedido = p_id_pedido
          AND id_producto = v_id_producto
        LIMIT 1;

        IF v_id_pedido_detalle IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: Uno de los productos solicitados no pertenece al pedido indicado.';
        END IF;

        -- Validar cantidad
        IF v_cantidad > v_cantidad_comprada THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: No se puede devolver una cantidad mayor a la comprada.';
        END IF;

        -- Insertar detalle de devoluciÃ³n
        INSERT INTO Devoluciones_Detalles (
            id_devolucion,
            id_pedido_detalle,
            cantidad_devuelta,
            motivo_devolucion,
            id_estado_devolucion,
            id_tipo_devoluciones
        ) VALUES (
            v_id_devolucion,
            v_id_pedido_detalle,
            v_cantidad,
            v_motivo,
            v_id_estado_pendiente,
            v_id_tipo
        );

        SET v_index = v_index + 1;
    END WHILE;

    COMMIT;

    SELECT v_id_devolucion AS id_devolucion_generada;
END$$

-- =========================================
-- facturacionDiaria
-- =========================================
CREATE OR REPLACE PROCEDURE facturacionDiaria(
    IN desde DATE,
    IN hasta DATE
)
BEGIN
    DECLARE fecha_actual DATE;

    SET fecha_actual = desde;

    DROP TEMPORARY TABLE IF EXISTS TmpFacturacion;

    CREATE TEMPORARY TABLE TmpFacturacion (
        fecha_reporte       DATE NOT NULL PRIMARY KEY,
        subtotal_facturado  DECIMAL(10, 2) NULL,
        impuestos_facturados DECIMAL(10, 2) NULL,
        total_facturado     DECIMAL(10, 2) NULL,
        conteo_facturas     INT NULL
    );

    miLoop: LOOP
        IF fecha_actual > hasta THEN
            LEAVE miLoop;
        END IF;

        INSERT INTO TmpFacturacion (
            fecha_reporte,
            subtotal_facturado,
            impuestos_facturados,
            total_facturado,
            conteo_facturas
        )
        SELECT
            fecha_actual AS fecha_reporte,
            IFNULL(SUM(f.subtotal), 0)  AS subtotal_facturado,
            IFNULL(SUM(f.impuestos), 0) AS impuestos_facturados,
            IFNULL(SUM(f.total), 0)     AS total_facturado,
            COUNT(DISTINCT f.id_factura) AS conteo_facturas
        FROM Facturas f
        JOIN Estados_Facturas ef
            ON ef.id_factura = f.id_factura
           AND ef.estado_factura = 'Pagada'
        WHERE DATE(f.fecha_emision) = fecha_actual;

        SET fecha_actual = DATE_ADD(fecha_actual, INTERVAL 1 DAY);
    END LOOP;

    IF (SELECT COALESCE(SUM(conteo_facturas),0) FROM TmpFacturacion) = 0 THEN
        SELECT 'No hubo facturas pagadas en este rango de fechas.' AS mensaje;
    ELSE
        SELECT *
        FROM TmpFacturacion
        ORDER BY fecha_reporte;
    END IF;
END$$

DELIMITER ;

DELIMITER $$

-- =========================================
-- inventarioAjustar
-- =========================================
CREATE OR REPLACE PROCEDURE inventarioAjustar(
    IN skuSP            VARCHAR(50),
    IN cantidadSP       INT,
    IN tipo_cambioSP    VARCHAR(20),   -- 'Entrada', 'Salida', 'Ajuste'
    IN nombre_sucursalSP VARCHAR(100),
    IN id_usuario_rolSP INT
)
BEGIN
  DECLARE IDtipo_cambio INT;
  DECLARE IDsku INT;
  DECLARE productoActivo INT;
  DECLARE sucursalActiva INT;
  DECLARE IDproducto INT;
  DECLARE IDcambio INT;
  DECLARE existeSucursalProducto INT;
  DECLARE nombre_sucursalSPF  VARCHAR(100);
  DECLARE IDSucursalProductoSP INT;
  DECLARE stock_actual_actual INT;
  DECLARE stock_maximo_actual INT;

  DECLARE v_mensaje VARCHAR(300);

  IF cantidadSP < 0 AND tipo_cambioSP = 'Ajuste' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad no puede ser menor que 0.';
  END IF;

  IF cantidadSP <= 0 AND (tipo_cambioSP = 'Entrada' OR tipo_cambioSP = 'Salida') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad debe ser positiva';
  END IF;

  SELECT id_tipo_cambio INTO IDtipo_cambio
  FROM Tipos_Cambios
  WHERE tipo_cambio = tipo_cambioSP;

  IF IDtipo_cambio IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El tipo de cambio no esta registrado';
  END IF;

  SET skuSP = UPPER(TRIM(skuSP));
  SELECT id_sku INTO IDsku FROM Sku WHERE sku = skuSP;

  IF IDsku IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sku no encontrado';
  END IF;

  SELECT id_producto INTO IDproducto
  FROM Productos
  WHERE id_sku = IDsku;

  IF IDproducto IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Producto no encontrado';
  END IF;

  SELECT activo_producto INTO productoActivo
  FROM Productos
  WHERE id_producto = IDproducto;

  IF productoActivo = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto estÃ¡ inactivo.';
  END IF;

  IF nombre_sucursalSP IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Se desconoce la sucursal';
  END IF;

  SET nombre_sucursalSP = TRIM(nombre_sucursalSP);
  SET nombre_sucursalSPF = '';

  -- Formatear nombre de sucursal (capitalizar cada palabra)
  WHILE LOCATE(' ', nombre_sucursalSP) > 0 DO
    SET nombre_sucursalSPF = CONCAT(
      nombre_sucursalSPF,
      UPPER(LEFT(SUBSTRING_INDEX(nombre_sucursalSP, ' ', 1), 1)),
      LOWER(SUBSTRING(SUBSTRING_INDEX(nombre_sucursalSP, ' ', 1), 2)),
      ' '
    );
    SET nombre_sucursalSP = SUBSTRING(nombre_sucursalSP, LOCATE(' ', nombre_sucursalSP) + 1);
  END WHILE;

  SET nombre_sucursalSPF = CONCAT(
    nombre_sucursalSPF,
    UPPER(LEFT(nombre_sucursalSP, 1)),
    LOWER(SUBSTRING(nombre_sucursalSP, 2))
  );

  SET nombre_sucursalSP = nombre_sucursalSPF;

  SELECT activo_sucursal INTO sucursalActiva
  FROM Sucursales
  WHERE nombre_sucursal = nombre_sucursalSP
  LIMIT 1;

  IF sucursalActiva = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La sucursal estÃ¡ inactiva.';
  END IF;

  SELECT sp.id_sucursal_producto,
         sp.stock_actual,
         sp.stock_maximo
    INTO IDSucursalProductoSP,
         stock_actual_actual,
         stock_maximo_actual
  FROM Sucursales_Productos sp
  JOIN Sucursales s ON sp.id_sucursal = s.id_sucursal
  WHERE sp.id_producto = IDproducto
    AND s.nombre_sucursal = nombre_sucursalSP
  LIMIT 1;

  IF IDSucursalProductoSP IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no existe en la sucursal indicada';
  END IF;

  -- Crear cambio
  INSERT INTO Cambios_Sucursal(id_usuario_rol, id_tipo_cambio, motivo_cambio)
    VALUES (id_usuario_rolSP, IDtipo_cambio, motivoSP);

  SELECT id_cambio INTO IDcambio
    FROM Cambios_Sucursal
    WHERE id_usuario_rol = id_usuario_rolSP
      AND id_tipo_cambio = IDtipo_cambio
      AND motivo_cambio = motivoSP
    ORDER BY fecha_cambio DESC
    LIMIT 1;

  -- Entrada
  IF tipo_cambioSP = 'Entrada' THEN

    IF (stock_actual_actual + cantidadSP) > stock_maximo_actual THEN
      SET v_mensaje = CONCAT(
        'Error: El stock no puede exceder el mÃ¡ximo. Stock actual: ',
        stock_actual_actual,
        ', cantidad a agregar: ',
        cantidadSP,
        ', stock mÃ¡ximo: ',
        stock_maximo_actual
      );
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    INSERT INTO Tipo_Entradas(id_cambio, id_sucursal_producto_destino, cantidad_entrada)
      VALUES (IDcambio, IDSucursalProductoSP, cantidadSP);

    UPDATE Sucursales_Productos
      SET stock_actual = stock_actual + cantidadSP
      WHERE id_sucursal_producto = IDSucursalProductoSP;

  -- Salida
  ELSEIF tipo_cambioSP = 'Salida' THEN

    IF stock_actual_actual < cantidadSP THEN
      SET v_mensaje = CONCAT(
        'Stock insuficiente. Stock actual: ',
        stock_actual_actual,
        ', cantidad solicitada: ',
        cantidadSP
      );
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    INSERT INTO Tipo_Salidas(id_cambio, id_sucursal_producto_origen, cantidad_salida)
      VALUES (IDcambio, IDSucursalProductoSP, cantidadSP);

    UPDATE Sucursales_Productos
      SET stock_actual = stock_actual - cantidadSP
      WHERE id_sucursal_producto = IDSucursalProductoSP;

  -- Ajuste
  ELSEIF tipo_cambioSP = 'Ajuste' THEN

    IF cantidadSP < 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad de ajuste no puede ser negativa';
    END IF;

    IF cantidadSP > stock_maximo_actual THEN
      SET v_mensaje = CONCAT(
        'Error: El stock no puede exceder el mÃ¡ximo. Cantidad de ajuste: ',
        cantidadSP,
        ', stock mÃ¡ximo: ',
        stock_maximo_actual
      );
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    INSERT INTO Tipo_Ajustes(id_cambio, id_sucursal_producto_ajuste, cantidad_ajuste)
      VALUES (IDcambio, IDSucursalProductoSP, cantidadSP);

    UPDATE Sucursales_Productos
      SET stock_actual = cantidadSP
      WHERE id_sucursal_producto = IDSucursalProductoSP;
  END IF;

END$$

-- =========================================
-- login
-- =========================================
CREATE OR REPLACE PROCEDURE login(
    IN nombre_usuarioSP VARCHAR(50)
)
BEGIN
    SELECT
        id_usuario,
        nombre_usuario,
        contrasena
    FROM Usuarios
    WHERE nombre_usuario = nombre_usuarioSP
    LIMIT 1;
END$$

-- =========================================
-- pagoRegistrar
-- =========================================
CREATE OR REPLACE PROCEDURE pagoRegistrar(
    IN var_id_factura     INT,
    IN var_id_metodo_pago INT,
    IN var_importe        DECIMAL(10,2)
)
BEGIN
    DECLARE validacion_total_factura DECIMAL(10,2);
    DECLARE var_id_pedido INT;
    DECLARE conteo_pagado_anterior DECIMAL(10,2);
    DECLARE calculo_total_acumulado DECIMAL(10,2);
    DECLARE var_id_pago_nuevo INT;
    DECLARE var_nuevo_estado VARCHAR(50);
    DECLARE var_pendiente DECIMAL(10,2);
    DECLARE var_factura_existe INT;
    DECLARE v_mensaje_error VARCHAR(255);

    -- Validar existencia de factura
    SELECT COUNT(*) INTO var_factura_existe
    FROM Facturas
    WHERE id_factura = var_id_factura;

    IF var_factura_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La factura no existe.';
    END IF;

    -- Obtener total y pedido
    SELECT id_pedido, total INTO var_id_pedido, validacion_total_factura
    FROM Facturas
    WHERE id_factura = var_id_factura
    LIMIT 1;

    IF validacion_total_factura IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: No se pudo obtener el total de la factura.';
    END IF;

    IF var_id_pedido IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: La factura no tiene un pedido asociado (id_pedido es NULL).';
    END IF;

    IF var_importe <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El importe debe ser mayor a cero.';
    END IF;

    -- Total pagado hasta ahora
    SELECT COALESCE(SUM(mp.monto_metodo_pago), 0)
    INTO conteo_pagado_anterior
    FROM Pagos p
    JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
    WHERE p.id_factura = var_id_factura;

    SET var_pendiente = validacion_total_factura - conteo_pagado_anterior;

    IF var_importe > var_pendiente THEN
        SET v_mensaje_error = CONCAT(
            'El importe no puede ser mayor al pendiente (',
            FORMAT(var_pendiente, 2),
            ').'
        );
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = v_mensaje_error;
    END IF;

    -- Crear pago
    INSERT INTO Pagos (id_factura, id_pedido, fecha_pago)
    VALUES (var_id_factura, var_id_pedido, CURDATE());

    SET var_id_pago_nuevo = LAST_INSERT_ID();

    -- Registrar monto
    INSERT INTO Montos_Pagos (id_metodo_pago, id_pago, monto_metodo_pago)
    VALUES (var_id_metodo_pago, var_id_pago_nuevo, var_importe);

    SET calculo_total_acumulado = conteo_pagado_anterior + var_importe;

    -- Determinar nuevo estado
    IF calculo_total_acumulado >= validacion_total_factura THEN
        SET var_nuevo_estado = 'Pagada';
    ELSE
        SET var_nuevo_estado = 'Parcial';
    END IF;

    -- Actualizar estado de factura
    DELETE FROM Estados_Facturas
    WHERE id_factura = var_id_factura;

    INSERT INTO Estados_Facturas (id_factura, estado_factura, fecha_estado_factura)
    VALUES (var_id_factura, var_nuevo_estado, CURDATE());

    SELECT
        CONCAT('Pago registrado. Nuevo estado: ', var_nuevo_estado) AS Mensaje,
        var_nuevo_estado AS Estado,
        calculo_total_acumulado AS Total_Pagado,
        (validacion_total_factura - calculo_total_acumulado) AS Pendiente;
END$$

DELIMITER ;

DELIMITER $$

-- =========================================
-- pedidoActualizarEstado
-- =========================================
CREATE OR REPLACE PROCEDURE pedidoActualizarEstado(
    IN id_pedidoSP      INT,
    IN estado_pedidoSP  VARCHAR(50)
)
BEGIN
    DECLARE IDestado_pedido INT;

    SELECT id_estado_pedido
    INTO IDestado_pedido
    FROM Estados_Pedidos
    WHERE estado_pedido = estado_pedidoSP
    LIMIT 1;

    IF IDestado_pedido IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: No se proporciono un estado de pedido vÃ¡lido.';
    END IF;

    UPDATE Pedidos
    SET id_estado_pedido = IDestado_pedido
    WHERE id_pedido = id_pedidoSP;
END$$

-- =========================================
-- pedidoCrear
-- =========================================
CREATE OR REPLACE PROCEDURE pedidoCrear(
    IN p_id_tmp_pedido INT
)
BEGIN
    DECLARE v_id_pedido INT;
    DECLARE v_id_cliente INT;
    DECLARE v_id_estado_confirmado INT;
    DECLARE v_id_usuario INT;
    DECLARE v_items_carrito INT;
    DECLARE v_items_sin_sucursal INT;
    DECLARE v_rfc CHAR(13);
    DECLARE v_id_direccion INT;
    DECLARE v_telefono VARCHAR(15);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Carrito temporal (por si no existen)
    CREATE TEMPORARY TABLE IF NOT EXISTS TmpPedidos (
        id_tmp_pedido INT AUTO_INCREMENT PRIMARY KEY,
        fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
        id_usuario INT NULL
    );

    CREATE TEMPORARY TABLE IF NOT EXISTS TmpItems_Pedido (
        id_tmp_item INT AUTO_INCREMENT PRIMARY KEY,
        id_producto INT NOT NULL,
        cantidad_producto INT NOT NULL,
        id_tmp_pedido INT NOT NULL
    );

    -- Sucursales seleccionadas
    DROP TEMPORARY TABLE IF EXISTS TmpSucursalesSeleccionadas;
    CREATE TEMPORARY TABLE TmpSucursalesSeleccionadas (
        id_producto INT NOT NULL,
        id_sucursal INT NOT NULL,
        cantidad_producto INT NOT NULL,
        PRIMARY KEY (id_producto)
    );

    -- Usuario del carrito
    SELECT id_usuario
    INTO v_id_usuario
    FROM TmpPedidos
    WHERE id_tmp_pedido = p_id_tmp_pedido
    LIMIT 1;

    IF v_id_usuario IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_CARRITO_INVALIDO';
    END IF;

    -- Items del carrito
    SELECT COUNT(*)
    INTO v_items_carrito
    FROM TmpItems_Pedido
    WHERE id_tmp_pedido = p_id_tmp_pedido;

    IF v_items_carrito = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_CARRITO_VACIO';
    END IF;

    -- Cliente
    SELECT id_cliente
    INTO v_id_cliente
    FROM Clientes
    WHERE id_usuario = v_id_usuario
    LIMIT 1;

    IF v_id_cliente IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_SIN_CLIENTE';
    END IF;

    -- Datos fiscales
    SELECT rfc_usuario, id_direccion, telefono
    INTO v_rfc, v_id_direccion, v_telefono
    FROM Usuarios
    WHERE id_usuario = v_id_usuario;

    IF v_rfc IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_FALTA_RFC';
    END IF;

    IF v_id_direccion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_FALTA_DIRECCION';
    END IF;

    IF v_telefono IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_FALTA_TELEFONO';
    END IF;

    -- Elegir sucursales para cada producto
    INSERT INTO TmpSucursalesSeleccionadas (id_producto, id_sucursal, cantidad_producto)
    SELECT
        t.id_producto,
        COALESCE(
            (
                SELECT sp2.id_sucursal
                FROM Sucursales_Productos sp2
                JOIN Sucursales s2 ON s2.id_sucursal = sp2.id_sucursal
                WHERE sp2.id_producto = t.id_producto
                  AND s2.activo_sucursal = 1
                  AND sp2.stock_actual >= t.cantidad_producto
                ORDER BY sp2.stock_actual DESC
                LIMIT 1
            ),
            (
                SELECT sp2.id_sucursal
                FROM Sucursales_Productos sp2
                JOIN Sucursales s2 ON s2.id_sucursal = sp2.id_sucursal
                WHERE sp2.id_producto = t.id_producto
                  AND s2.activo_sucursal = 1
                ORDER BY sp2.stock_actual DESC
                LIMIT 1
            )
        ) AS id_sucursal,
        t.cantidad_producto
    FROM TmpItems_Pedido t
    WHERE t.id_tmp_pedido = p_id_tmp_pedido;

    -- Validar sucursal asignada
    SELECT COUNT(*)
    INTO v_items_sin_sucursal
    FROM TmpItems_Pedido t
    WHERE t.id_tmp_pedido = p_id_tmp_pedido
      AND NOT EXISTS (
          SELECT 1
          FROM TmpSucursalesSeleccionadas tss
          WHERE tss.id_producto = t.id_producto
            AND tss.id_sucursal IS NOT NULL
      );

    IF v_items_sin_sucursal > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_STOCK_INSUFICIENTE';
    END IF;

    IF v_id_cliente IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_SIN_CLIENTE';
    END IF;

    -- Estado "Confirmado"
    SELECT id_estado_pedido
    INTO v_id_estado_confirmado
    FROM Estados_Pedidos
    WHERE estado_pedido = 'Confirmado'
    LIMIT 1;

    IF v_id_estado_confirmado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_ESTADO_NO_EXISTE';
    END IF;

    -- Crear pedido
    INSERT INTO Pedidos (id_estado_pedido)
    VALUES (v_id_estado_confirmado);

    SET v_id_pedido = LAST_INSERT_ID();

    IF v_id_pedido IS NULL OR v_id_pedido = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_NO_SE_PUDO_CREAR_PEDIDO';
    END IF;

    -- Asignar cliente al pedido
    INSERT INTO Pedidos_Clientes (id_pedido, id_cliente)
    VALUES (v_id_pedido, v_id_cliente);

    IF NOT EXISTS (
        SELECT 1
        FROM Pedidos_Clientes
        WHERE id_pedido = v_id_pedido
          AND id_cliente = v_id_cliente
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_NO_SE_PUDO_ASOCIAR_CLIENTE';
    END IF;

    -- Detalles del pedido
    INSERT INTO Pedidos_Detalles (id_sucursal, id_pedido, id_producto, cantidad_producto)
    SELECT
        COALESCE(tss.id_sucursal, NULL) AS id_sucursal,
        v_id_pedido,
        tss.id_producto,
        tss.cantidad_producto
    FROM TmpSucursalesSeleccionadas tss;

    -- ValidaciÃ³n final
    IF NOT EXISTS (
        SELECT 1
        FROM Pedidos_Clientes
        WHERE id_pedido = v_id_pedido
          AND id_cliente IS NOT NULL
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR_PEDIDO_SIN_CLIENTE_FINAL';
    END IF;

    -- Limpiar temporales
    DELETE FROM TmpItems_Pedido WHERE id_tmp_pedido = p_id_tmp_pedido;
    DELETE FROM TmpPedidos      WHERE id_tmp_pedido = p_id_tmp_pedido;
    DROP TEMPORARY TABLE IF EXISTS TmpSucursalesSeleccionadas;

    COMMIT;
END$$

-- =========================================
-- pedidoFacturar
-- =========================================
CREATE OR REPLACE PROCEDURE pedidoFacturar(
    IN id_pedidoSP INT
)
BEGIN
    DECLARE id_empresaSP INT;
    DECLARE subtotalSP DECIMAL(10,2);
    DECLARE existeFactura INT;
    DECLARE existePedido INT;
    DECLARE impuestos DECIMAL(10,2);
    DECLARE total DECIMAL(10,2);
    DECLARE idFacturaNueva INT;
    DECLARE tienePagos INT;
    DECLARE total_pagado DECIMAL(10,2) DEFAULT 0;

    -- Empresa fija (buscar por nombre que contenga "Auralisse" para evitar problemas de encoding)
    SELECT id_empresa
    INTO id_empresaSP
    FROM Empresas
    WHERE nombre_empresa LIKE 'Auralisse%'
    LIMIT 1;

    -- Validar que se encontró la empresa
    IF id_empresaSP IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No se encontró la empresa "Auralisse Joyería" en el sistema. Contacte al administrador.';
    END IF;

    -- Pedido existe
    SELECT COUNT(*)
    INTO existePedido
    FROM Pedidos
    WHERE id_pedido = id_pedidoSP;

    IF existePedido = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El pedido no existe.';
    END IF;

    -- No tenga factura previa
    SELECT COUNT(*)
    INTO existeFactura
    FROM Facturas
    WHERE id_pedido = id_pedidoSP;

    IF existeFactura > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El pedido ya tiene una factura registrada.';
    END IF;

    -- Total con descuento
    SELECT SUM(
        (pr.precio_unitario - (pr.precio_unitario * COALESCE(pr.descuento_producto, 0) / 100))
        * pd.cantidad_producto
    )
    INTO total
    FROM Pedidos_Detalles pd
    JOIN Productos pr ON pr.id_producto = pd.id_producto
    WHERE pd.id_pedido = id_pedidoSP;

    -- Calcular subtotal e impuestos (IVA 16%)
    SET subtotalSP = total / 1.16;
    SET impuestos  = total - subtotalSP;

    -- Crear factura
    INSERT INTO Facturas (folio, id_pedido, id_empresa, subtotal, impuestos, total)
    VALUES (UUID(), id_pedidoSP, id_empresaSP, subtotalSP, impuestos, total);

    SET idFacturaNueva = LAST_INSERT_ID();

    -- Asociar pagos existentes del pedido (que tienen id_factura = NULL) a la factura nueva
    UPDATE Pagos
    SET id_factura = idFacturaNueva
    WHERE id_pedido = id_pedidoSP 
    AND id_factura IS NULL;

    -- Verificar pagos asociados a la factura
    SELECT COUNT(*)
    INTO tienePagos
    FROM Pagos
    WHERE id_factura = idFacturaNueva;

    -- Calcular total pagado para determinar el estado
    SELECT COALESCE(SUM(mp.monto_metodo_pago), 0)
    INTO total_pagado
    FROM Pagos p
    JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
    WHERE p.id_factura = idFacturaNueva;

    -- Estado de factura basado en el total pagado
    INSERT INTO Estados_Facturas (id_factura, estado_factura, fecha_estado_factura)
    VALUES (
        idFacturaNueva,
        CASE
            WHEN total_pagado >= total THEN 'Pagada'
            WHEN total_pagado > 0 THEN 'Parcial'
            ELSE 'Pendiente'
        END,
        CURDATE()
    );
END$$

-- =========================================
-- pedido_cancelar
-- =========================================
CREATE OR REPLACE PROCEDURE pedido_cancelar(
    IN var_id_pedido       INT,
    IN var_id_usuario_rol  INT,
    IN var_motivo_cancelacion VARCHAR(255)
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE conteo_id_producto INT;
    DECLARE conteo_id_sucursal INT;
    DECLARE conteo_cantidad INT;
    DECLARE conteo_id_sucursal_producto INT;

    DECLARE validacion_estado_actual INT;

    DECLARE cur_pedido CURSOR FOR
        SELECT id_producto, id_sucursal, cantidad_producto
        FROM Pedidos_Detalles
        WHERE id_pedido = var_id_pedido;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Estado actual del pedido
    SELECT id_estado_pedido
    INTO validacion_estado_actual
    FROM Pedidos
    WHERE id_pedido = var_id_pedido;

    -- Ej: 3 y 4 = estados finales (ajusta segÃºn tu catÃ¡logo)
    IF validacion_estado_actual IN (3, 4) THEN
        SELECT 'Error: El pedido no se puede cancelar.' AS Mensaje;
    ELSE
        -- Cambiar a "Cancelado"
        UPDATE Pedidos
        SET id_estado_pedido = 4
        WHERE id_pedido = var_id_pedido;

        -- Devolver stock
        OPEN cur_pedido;

        read_loop: LOOP
            FETCH cur_pedido
            INTO conteo_id_producto, conteo_id_sucursal, conteo_cantidad;

            IF done THEN
                LEAVE read_loop;
            END IF;

            SELECT id_sucursal_producto
            INTO conteo_id_sucursal_producto
            FROM Sucursales_Productos
            WHERE id_sucursal = conteo_id_sucursal
              AND id_producto = conteo_id_producto;

            UPDATE Sucursales_Productos
            SET stock_actual = stock_actual + conteo_cantidad
            WHERE id_sucursal_producto = conteo_id_sucursal_producto;
        END LOOP;

        CLOSE cur_pedido;

        -- Registrar cambio de sucursal (auditorÃ­a de cancelaciÃ³n)
        INSERT INTO Cambios_Sucursal (id_usuario_rol, id_tipo_cambio, motivo_cambio)
        VALUES (var_id_usuario_rol, 1, CONCAT('CancelaciÃ³n Pedido #', var_id_pedido, ': ', var_motivo_cancelacion));

        SELECT 'Pedido cancelado y stock devuelto correctamente.' AS Mensaje;
    END IF;
END$$

-- =========================================

-- =========================================
-- productoActualizar
-- =========================================
CREATE OR REPLACE PROCEDURE productoActualizar(
    IN skuSP                VARCHAR(20),
    IN nombre_categoriaSP   VARCHAR(100),
    IN materialSP           VARCHAR(100),
    IN genero_productoSP    VARCHAR(50),
    IN nombre_productoSP    VARCHAR(150),
    IN precio_unitarioSP    DECIMAL(10,2),
    IN descuento_productoSP DECIMAL(5,2),
    IN costo_unitarioSP     DECIMAL(10,2),
    IN activo_productoSP    TINYINT,
    IN tallaSP              VARCHAR(20),
    IN kilatajeSP           VARCHAR(10),
    IN leySP                DECIMAL(10,2)
)
BEGIN
    DECLARE IDsku INT;
    DECLARE IDproducto INT;
    DECLARE IDmodelo INT;
    DECLARE IDcategoria INT;
    DECLARE IDmaterial INT;
    DECLARE IDgenero INT;
    DECLARE filaOro INT;
    DECLARE filaPlata INT;
    DECLARE v_mensaje_error VARCHAR(500);

    -- Buscar SKU
    SELECT id_sku
    INTO IDsku
    FROM Sku
    WHERE sku = UPPER(TRIM(skuSP));

    IF IDsku IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El SKU no existe, no se puede actualizar';
    END IF;

    -- Producto / modelo / material actual
    SELECT id_producto, id_modelo, id_material
    INTO IDproducto, IDmodelo, IDmaterial
    FROM Productos
    WHERE id_sku = IDsku;

    -- CategorÃ­a
    IF nombre_categoriaSP IS NOT NULL THEN
        SET nombre_categoriaSP = CONCAT(
            UPPER(SUBSTR(TRIM(nombre_categoriaSP),1,1)),
            LOWER(SUBSTR(TRIM(nombre_categoriaSP),2))
        );

        SELECT id_categoria
        INTO IDcategoria
        FROM Categorias
        WHERE nombre_categoria = nombre_categoriaSP;

        IF IDcategoria IS NULL THEN
            INSERT INTO Categorias(nombre_categoria, activo_categoria)
            VALUES (nombre_categoriaSP, TRUE);

            SELECT id_categoria
            INTO IDcategoria
            FROM Categorias
            WHERE nombre_categoria = nombre_categoriaSP;
        END IF;
    END IF;

    -- Material
    IF materialSP IS NOT NULL THEN
        SET materialSP = CONCAT(
            UPPER(SUBSTR(TRIM(materialSP),1,1)),
            LOWER(SUBSTR(TRIM(materialSP),2))
        );

        SELECT id_material
        INTO IDmaterial
        FROM Materiales
        WHERE material = materialSP;

        IF IDmaterial IS NULL THEN
            INSERT INTO Materiales(material)
            VALUES (materialSP);

            SELECT id_material
            INTO IDmaterial
            FROM Materiales
            WHERE material = materialSP;
        END IF;
    ELSE
        SELECT m.material, m.id_material
        INTO materialSP, IDmaterial
        FROM Materiales m
        JOIN Productos p ON p.id_material = m.id_material
        WHERE p.id_producto = IDproducto;
    END IF;

    -- GÃ©nero
    IF genero_productoSP IS NOT NULL THEN
        SET genero_productoSP = CONCAT(
            UPPER(SUBSTR(TRIM(genero_productoSP),1,1)),
            LOWER(SUBSTR(TRIM(genero_productoSP),2))
        );

        SELECT id_genero_producto
        INTO IDgenero
        FROM Generos_Productos
        WHERE genero_producto = genero_productoSP;
    END IF;

    -- Actualizar modelo
    IF nombre_productoSP IS NOT NULL THEN
        UPDATE Modelos
        SET nombre_producto = nombre_productoSP
        WHERE id_modelo = IDmodelo;
    END IF;

    IF IDcategoria IS NOT NULL THEN
        UPDATE Modelos
        SET id_categoria = IDcategoria
        WHERE id_modelo = IDmodelo;
    END IF;

    IF IDgenero IS NOT NULL THEN
        UPDATE Modelos
        SET id_genero_producto = IDgenero
        WHERE id_modelo = IDmodelo;
    END IF;

    -- Producto
    IF IDmaterial IS NOT NULL THEN
        UPDATE Productos
        SET id_material = IDmaterial
        WHERE id_producto = IDproducto;
    END IF;

    IF precio_unitarioSP IS NOT NULL THEN
        UPDATE Productos
        SET precio_unitario = precio_unitarioSP
        WHERE id_producto = IDproducto;
    END IF;

    IF descuento_productoSP IS NOT NULL THEN
        UPDATE Productos
        SET descuento_producto = descuento_productoSP
        WHERE id_producto = IDproducto;
    END IF;

    IF costo_unitarioSP IS NOT NULL THEN
        UPDATE Productos
        SET costo_unitario = costo_unitarioSP
        WHERE id_producto = IDproducto;
    END IF;

    IF activo_productoSP IS NOT NULL THEN
        UPDATE Productos
        SET activo_producto = activo_productoSP
        WHERE id_producto = IDproducto;
    END IF;

    -- Tallas (solo Anillos)
    IF nombre_categoriaSP = 'Anillos' AND tallaSP IS NOT NULL THEN
        SET tallaSP = TRIM(tallaSP);

        INSERT INTO Tallas_Productos (id_producto, talla)
        VALUES (IDproducto, tallaSP)
        ON DUPLICATE KEY UPDATE talla = tallaSP;
    END IF;

    -- Oro / kilataje
    IF kilatajeSP IS NOT NULL THEN
        IF materialSP <> 'Oro' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No se puede asignar kilataje a un producto que no es Oro';
        ELSE
            UPDATE Productos_Oro_Kilataje
            SET kilataje = kilatajeSP
            WHERE id_producto = IDproducto;
        END IF;
    END IF;

    IF materialSP = 'Oro' THEN
        DELETE FROM Productos_Plata_Ley
        WHERE id_producto = IDproducto;

        SELECT COUNT(*)
        INTO filaOro
        FROM Productos_Oro_Kilataje
        WHERE id_producto = IDproducto;

        IF filaOro = 0 THEN
            INSERT INTO Productos_Oro_Kilataje (id_producto)
            VALUES (IDproducto);
        END IF;
    END IF;

    -- Plata / ley
    IF leySP IS NOT NULL THEN
        IF materialSP <> 'Plata' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No se puede asignar ley a un producto que no es Plata';
        ELSE
            UPDATE Productos_Plata_Ley
            SET ley = leySP
            WHERE id_producto = IDproducto;
        END IF;
    END IF;

    IF materialSP = 'Plata' THEN
        DELETE FROM Productos_Oro_Kilataje
        WHERE id_producto = IDproducto;

        SELECT COUNT(*)
        INTO filaPlata
        FROM Productos_Plata_Ley
        WHERE id_producto = IDproducto;

        IF filaPlata = 0 THEN
            INSERT INTO Productos_Plata_Ley (id_producto)
            VALUES (IDproducto);
        END IF;
    END IF;
END$$

-- =========================================
-- productoActualizar
-- =========================================
CREATE OR REPLACE PROCEDURE productoActualizar(
    IN skuSP                VARCHAR(20),
    IN nombre_categoriaSP   VARCHAR(100),
    IN materialSP           VARCHAR(100),
    IN genero_productoSP    VARCHAR(50),
    IN nombre_productoSP    VARCHAR(150),
    IN precio_unitarioSP    DECIMAL(10,2),
    IN descuento_productoSP DECIMAL(5,2),
    IN costo_unitarioSP     DECIMAL(10,2),
    IN activo_productoSP    TINYINT,
    IN tallaSP              VARCHAR(20),
    IN kilatajeSP           INT,
    IN leySP                DECIMAL(10,2)
)
BEGIN
    DECLARE IDsku INT;
    DECLARE IDproducto INT;
    DECLARE IDmodelo INT;
    DECLARE IDcategoria INT;
    DECLARE IDmaterial INT;
    DECLARE IDgenero INT;
    DECLARE filaOro INT;
    DECLARE filaPlata INT;

    -- Buscar SKU
    SELECT id_sku
    INTO IDsku
    FROM Sku
    WHERE sku = UPPER(TRIM(skuSP));

    IF IDsku IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El SKU no existe, no se puede actualizar';
    END IF;

    -- Producto / modelo / material actual
    SELECT id_producto, id_modelo, id_material
    INTO IDproducto, IDmodelo, IDmaterial
    FROM Productos
    WHERE id_sku = IDsku;

    -- CategorÃ­a
    IF nombre_categoriaSP IS NOT NULL THEN
        SET nombre_categoriaSP = CONCAT(
            UPPER(SUBSTR(TRIM(nombre_categoriaSP),1,1)),
            LOWER(SUBSTR(TRIM(nombre_categoriaSP),2))
        );

        SELECT id_categoria
        INTO IDcategoria
        FROM Categorias
        WHERE nombre_categoria = nombre_categoriaSP;

        IF IDcategoria IS NULL THEN
            INSERT INTO Categorias(nombre_categoria)
            VALUES (nombre_categoriaSP);

            SELECT id_categoria
            INTO IDcategoria
            FROM Categorias
            WHERE nombre_categoria = nombre_categoriaSP;
        END IF;
    END IF;

    -- Material
    IF materialSP IS NOT NULL THEN
        SET materialSP = CONCAT(
            UPPER(SUBSTR(TRIM(materialSP),1,1)),
            LOWER(SUBSTR(TRIM(materialSP),2))
        );

        SELECT id_material
        INTO IDmaterial
        FROM Materiales
        WHERE material = materialSP;

        IF IDmaterial IS NULL THEN
            INSERT INTO Materiales(material)
            VALUES (materialSP);

            SELECT id_material
            INTO IDmaterial
            FROM Materiales
            WHERE material = materialSP;
        END IF;
    ELSE
        SELECT m.material, m.id_material
        INTO materialSP, IDmaterial
        FROM Materiales m
        JOIN Productos p ON p.id_material = m.id_material
        WHERE p.id_producto = IDproducto;
    END IF;

    -- GÃ©nero
    IF genero_productoSP IS NOT NULL THEN
        SET genero_productoSP = CONCAT(
            UPPER(SUBSTR(TRIM(genero_productoSP),1,1)),
            LOWER(SUBSTR(TRIM(genero_productoSP),2))
        );

        SELECT id_genero_producto
        INTO IDgenero
        FROM Generos_Productos
        WHERE genero_producto = genero_productoSP;
    END IF;

    -- Actualizar modelo
    IF nombre_productoSP IS NOT NULL THEN
        UPDATE Modelos
        SET nombre_producto = nombre_productoSP
        WHERE id_modelo = IDmodelo;
    END IF;

    IF IDcategoria IS NOT NULL THEN
        UPDATE Modelos
        SET id_categoria = IDcategoria
        WHERE id_modelo = IDmodelo;
    END IF;

    IF IDgenero IS NOT NULL THEN
        UPDATE Modelos
        SET id_genero_producto = IDgenero
        WHERE id_modelo = IDmodelo;
    END IF;

    -- Producto
    IF IDmaterial IS NOT NULL THEN
        UPDATE Productos
        SET id_material = IDmaterial
        WHERE id_producto = IDproducto;
    END IF;

    IF precio_unitarioSP IS NOT NULL THEN
        UPDATE Productos
        SET precio_unitario = precio_unitarioSP
        WHERE id_producto = IDproducto;
    END IF;

    IF descuento_productoSP IS NOT NULL THEN
        UPDATE Productos
        SET descuento_producto = descuento_productoSP
        WHERE id_producto = IDproducto;
    END IF;

    IF costo_unitarioSP IS NOT NULL THEN
        UPDATE Productos
        SET costo_unitario = costo_unitarioSP
        WHERE id_producto = IDproducto;
    END IF;

    IF activo_productoSP IS NOT NULL THEN
        UPDATE Productos
        SET activo_producto = activo_productoSP
        WHERE id_producto = IDproducto;
    END IF;

    -- Tallas (solo Anillos)
    IF nombre_categoriaSP = 'Anillos' AND tallaSP IS NOT NULL THEN
        SET tallaSP = TRIM(tallaSP);

        INSERT INTO Tallas_Productos (id_producto, talla)
        VALUES (IDproducto, tallaSP)
        ON DUPLICATE KEY UPDATE talla = tallaSP;
    END IF;

    -- Oro / kilataje
    IF kilatajeSP IS NOT NULL THEN
        IF materialSP <> 'Oro' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No se puede asignar kilataje a un producto que no es Oro';
        ELSE
            UPDATE Productos_Oro_Kilataje
            SET kilataje = kilatajeSP
            WHERE id_producto = IDproducto;
        END IF;
    END IF;

    IF materialSP = 'Oro' THEN
        DELETE FROM Productos_Plata_Ley
        WHERE id_producto = IDproducto;

        SELECT COUNT(*)
        INTO filaOro
        FROM Productos_Oro_Kilataje
        WHERE id_producto = IDproducto;

        IF filaOro = 0 THEN
            INSERT INTO Productos_Oro_Kilataje (id_producto)
            VALUES (IDproducto);
        END IF;
    END IF;

    -- Plata / ley
    IF leySP IS NOT NULL THEN
        IF materialSP <> 'Plata' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No se puede asignar ley a un producto que no es Plata';
        ELSE
            UPDATE Productos_Plata_Ley
            SET ley = leySP
            WHERE id_producto = IDproducto;
        END IF;
    END IF;

    IF materialSP = 'Plata' THEN
        DELETE FROM Productos_Oro_Kilataje
        WHERE id_producto = IDproducto;

        SELECT COUNT(*)
        INTO filaPlata
        FROM Productos_Plata_Ley
        WHERE id_producto = IDproducto;

        IF filaPlata = 0 THEN
            INSERT INTO Productos_Plata_Ley (id_producto)
            VALUES (IDproducto);
        END IF;
    END IF;
END$$
DELIMITER $$
-- =========================================

-- =========================================
-- productoImagenAgregar
-- =========================================
CREATE OR REPLACE PROCEDURE productoImagenAgregar(
    IN p_sku        VARCHAR(20),
    IN p_url_imagen VARCHAR(500)
)
BEGIN
    DECLARE v_id_producto INT DEFAULT NULL;
    DECLARE v_id_sku INT DEFAULT NULL;

    IF p_sku IS NULL OR TRIM(p_sku) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: El SKU es requerido';
    END IF;

    IF p_url_imagen IS NULL OR TRIM(p_url_imagen) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: La URL de la imagen es requerida';
    END IF;

    SELECT id_sku
    INTO v_id_sku
    FROM Sku
    WHERE UPPER(sku) = UPPER(TRIM(p_sku))
    LIMIT 1;

    IF v_id_sku IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: El SKU no existe';
    END IF;

    SELECT id_producto
    INTO v_id_producto
    FROM Productos
    WHERE id_sku = v_id_sku
    LIMIT 1;

    IF v_id_producto IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No se encontrÃ³ un producto asociado al SKU';
    END IF;

    INSERT INTO Imagenes_Productos (id_producto, url_imagen)
    VALUES (v_id_producto, TRIM(p_url_imagen));

    SELECT LAST_INSERT_ID() AS id_imagen_producto;
END$$

DELIMITER ;

DELIMITER $$

-- =========================================
-- productosCatalogo
-- =========================================
CREATE OR REPLACE PROCEDURE productosCatalogo(
    IN p_nombre_categoria VARCHAR(100)
)
BEGIN
    IF p_nombre_categoria IS NOT NULL AND p_nombre_categoria <> '' THEN
        SELECT
            p.id_producto,
            m.nombre_producto AS nombre,
            p.precio_unitario AS precio_original,
            COALESCE(p.descuento_producto, 0) AS descuento_producto,
            (p.precio_unitario - (p.precio_unitario * COALESCE(p.descuento_producto, 0) / 100)) AS precio,
            s.sku,
            c.nombre_categoria,
            c.id_categoria,
            (SELECT ip.url_imagen
             FROM Imagenes_Productos ip
             WHERE ip.id_producto = p.id_producto
             ORDER BY ip.fecha_carga DESC
             LIMIT 1) AS imagen_url
        FROM Productos p
        JOIN Modelos m ON p.id_modelo = m.id_modelo
        JOIN Sku s ON p.id_sku = s.id_sku
        JOIN Categorias c ON m.id_categoria = c.id_categoria
        WHERE p.activo_producto = 1
          AND c.nombre_categoria = p_nombre_categoria
        ORDER BY m.nombre_producto;
    ELSE
        SELECT
            p.id_producto,
            m.nombre_producto AS nombre,
            p.precio_unitario AS precio_original,
            COALESCE(p.descuento_producto, 0) AS descuento_producto,
            (p.precio_unitario - (p.precio_unitario * COALESCE(p.descuento_producto, 0) / 100)) AS precio,
            s.sku,
            c.nombre_categoria,
            c.id_categoria,
            (SELECT ip.url_imagen
             FROM Imagenes_Productos ip
             WHERE ip.id_producto = p.id_producto
             ORDER BY ip.fecha_carga DESC
             LIMIT 1) AS imagen_url
        FROM Productos p
        JOIN Modelos m ON p.id_modelo = m.id_modelo
        JOIN Sku s ON p.id_sku = s.id_sku
        JOIN Categorias c ON m.id_categoria = c.id_categoria
        WHERE p.activo_producto = 1
        ORDER BY m.nombre_producto;
    END IF;
END$$

-- =========================================
-- producto_info_carrito
-- =========================================
CREATE OR REPLACE PROCEDURE producto_info_carrito(
    IN p_id_producto INT
)
BEGIN
    SELECT
        p.id_producto,
        m.nombre_producto AS nombre,
        p.precio_unitario AS precio,
        COALESCE(p.descuento_producto, 0) AS descuento_producto,
        s.sku
    FROM Productos p
    INNER JOIN Modelos m ON p.id_modelo = m.id_modelo
    INNER JOIN Sku s ON p.id_sku = s.id_sku
    WHERE p.id_producto = p_id_producto
      AND p.activo_producto = 1;
END$$

-- =========================================
-- registroCliente
-- =========================================
CREATE OR REPLACE PROCEDURE registroCliente(
    IN username        VARCHAR(50),
    IN nombre          VARCHAR(50),
    IN segundoNombre   VARCHAR(50),
    IN apellidoPaterno VARCHAR(50),
    IN apellidoMaterno VARCHAR(50),
    IN contrasenaSP    VARCHAR(255)
)
BEGIN
    INSERT INTO Usuarios (
        nombre_usuario,
        nombre_primero,
        nombre_segundo,
        apellido_paterno,
        apellido_materno,
        contrasena
    )
    VALUES (
        username,
        nombre,
        NULLIF(segundoNombre, ''),
        apellidoPaterno,
        NULLIF(apellidoMaterno, ''),
        contrasenaSP
    );
END$$

-- =========================================
-- reingresoInventario
-- =========================================
CREATE OR REPLACE PROCEDURE reingresoInventario(
    IN id_devolucionSP INT,
    IN id_usuario_rolSP INT
)
BEGIN
    DECLARE existeDevolucion INT;
    DECLARE IDestadoAutorizado  INT;
    DECLARE IDtipocambio INT;
    DECLARE IDtipodevolucion INT;
    DECLARE IDtipoDevolucioncambio INT;
    DECLARE IDestado INT;
    DECLARE v_id_cambio INT;

    SELECT COUNT(*) INTO existeDevolucion
    FROM Devoluciones
    WHERE id_devolucion = id_devolucionSP;

    IF existeDevolucion = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La devoluciÃ³n no existe.';
    END IF;

    SELECT id_estado_devolucion INTO IDestadoAutorizado
    FROM Estados_Devoluciones
    WHERE estado_devolucion = 'Autorizado'
    LIMIT 1;

    IF IDestadoAutorizado IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: No existe el estado Autorizado.';
    END IF;

    SELECT dd.id_estado_devolucion
    INTO IDestado
    FROM Devoluciones_Detalles dd
    WHERE dd.id_devolucion = id_devolucionSP
    LIMIT 1;

    IF IDestado <> IDestadoAutorizado THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La devoluciÃ³n no estÃ¡ autorizada.';
    END IF;

    SELECT td.id_tipo_devoluciones
    INTO IDtipodevolucion
    FROM Devoluciones_Detalles dd
    JOIN Tipos_Devoluciones td
        ON td.id_tipo_devoluciones = dd.id_tipo_devoluciones
    WHERE dd.id_devolucion = id_devolucionSP
    LIMIT 1;

    SELECT id_tipo_devolucion
    INTO IDtipoDevolucioncambio
    FROM Tipos_Devoluciones
    WHERE tipo_devolucion = 'Cambio';

    IF IDtipoDevolucioncambio <> IDtipodevolucion THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Las devoluciones de tipo Cambio NO generan reingreso a inventario.';
    END IF;

    SELECT id_tipo_cambio
    INTO IDtipocambio
    FROM Tipos_Cambios
    WHERE tipo_cambio = 'Entrada'
    LIMIT 1;

    IF IDtipocambio IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: No existe el tipo de cambio Entrada.';
    END IF;

    INSERT INTO Cambios_Sucursal(id_usuario_rol, id_tipo_cambio, motivo_cambio)
    VALUES(id_usuario_rolSP, IDtipocambio, 'Reingreso por devoluciÃ³n autorizada');

    SELECT id_cambio
    INTO v_id_cambio
    FROM Cambios_Sucursal
    ORDER BY fecha_cambio DESC
    LIMIT 1;

    INSERT INTO Tipo_Entradas(id_cambio, id_sucursal_producto_destino, cantidad_entrada)
    SELECT
        v_id_cambio,
        pd.id_sucursal,
        dd.cantidad_devuelta
    FROM Devoluciones_Detalles dd
    JOIN Pedidos_Detalles pd
        ON pd.id_pedido_detalle = dd.id_pedido_detalle
    WHERE dd.id_devolucion = id_devolucionSP;
END$$

-- =========================================
-- sp_categorias_obtener_todos
-- =========================================
CREATE OR REPLACE PROCEDURE sp_categorias_obtener_todos()
BEGIN
    SELECT
        id_categoria,
        nombre_categoria
    FROM Categorias
    WHERE activo_categoria = 1
    ORDER BY nombre_categoria ASC;
END$$

-- =========================================
-- sp_clasificaciones_lista
-- =========================================
CREATE OR REPLACE PROCEDURE sp_clasificaciones_lista()
BEGIN
    SELECT
        id_clasificacion,
        nombre_clasificacion
    FROM Clasificaciones
    ORDER BY nombre_clasificacion;
END$$

-- =========================================
-- sp_clientes_lista_pedido
-- =========================================
CREATE OR REPLACE PROCEDURE sp_clientes_lista_pedido()
BEGIN
    SELECT
        cl.id_cliente,
        CONCAT(
            u.nombre_primero, ' ',
            IFNULL(u.nombre_segundo, ''), ' ',
            u.apellido_paterno, ' ',
            IFNULL(u.apellido_materno, '')
        ) AS nombre_completo,
        u.nombre_usuario,
        u.correo,
        u.telefono
    FROM Clientes cl
    JOIN Usuarios u ON cl.id_usuario = u.id_usuario
    WHERE u.activo_usuario = 1
    ORDER BY u.apellido_paterno, u.nombre_primero;
END$$

-- =========================================
-- sp_clientes_recurrentes
-- =========================================
CREATE OR REPLACE PROCEDURE sp_clientes_recurrentes()
BEGIN
    SELECT * FROM vClientesRecurrentes;
END$$

-- =========================================
-- sp_clientes_recurrentes_count
-- =========================================
CREATE OR REPLACE PROCEDURE sp_clientes_recurrentes_count()
BEGIN
    SELECT COUNT(DISTINCT id_cliente) AS total
    FROM vClientesRecurrentes;
END$$

-- =========================================
-- sp_cliente_max_id
-- =========================================
CREATE OR REPLACE PROCEDURE sp_cliente_max_id()
BEGIN
    SELECT MAX(id_cliente) AS id_cliente
    FROM Clientes;
END$$

-- =========================================
-- sp_cliente_obtener_usuario
-- =========================================
CREATE OR REPLACE PROCEDURE sp_cliente_obtener_usuario(
    IN p_id_cliente INT
)
BEGIN
    SELECT id_usuario
    FROM Clientes
    WHERE id_cliente = p_id_cliente;
END$$

-- =========================================
-- sp_codigos_postales_por_estado
-- =========================================
CREATE OR REPLACE PROCEDURE sp_codigos_postales_por_estado(
    IN p_id_estado INT
)
BEGIN
    SELECT DISTINCT
        cp.id_cp,
        cp.codigo_postal
    FROM Codigos_Postales cp
    JOIN Codigos_Postales_Estados cpe ON cp.id_cp = cpe.id_cp
    WHERE cpe.id_estado_direccion = p_id_estado
    ORDER BY cp.codigo_postal;
END$$

-- =========================================
-- sp_devoluciones_count_rango
-- =========================================
CREATE OR REPLACE PROCEDURE sp_devoluciones_count_rango(
    IN p_fecha_desde DATE,
    IN p_fecha_hasta DATE
)
BEGIN
    SELECT COUNT(*) AS total_devoluciones
    FROM Devoluciones d
    WHERE DATE(d.fecha_devolucion) BETWEEN p_fecha_desde AND p_fecha_hasta;
END$$

-- =========================================
-- sp_devoluciones_lista_admin
-- =========================================
CREATE OR REPLACE PROCEDURE sp_devoluciones_lista_admin()
BEGIN
    SELECT
        d.id_devolucion,
        d.id_pedido,
        d.fecha_devolucion,
        MIN(ed.estado_devolucion) AS estado_devolucion,
        MIN(td.tipo_devolucion) AS tipo_devolucion,
        COUNT(DISTINCT dd.id_devolucion_detalle) AS cantidad_productos,
        GROUP_CONCAT(DISTINCT ed.estado_devolucion) AS estados_disponibles
    FROM Devoluciones d
    LEFT JOIN Devoluciones_Detalles dd ON d.id_devolucion = dd.id_devolucion
    LEFT JOIN Estados_Devoluciones ed ON dd.id_estado_devolucion = ed.id_estado_devolucion
    LEFT JOIN Tipos_Devoluciones td ON dd.id_tipo_devoluciones = td.id_tipo_devoluciones
    GROUP BY d.id_devolucion, d.id_pedido, d.fecha_devolucion
    ORDER BY d.fecha_devolucion DESC, d.id_devolucion DESC
    LIMIT 100;
END$$

-- =========================================
-- sp_devoluciones_lista_ventas
-- =========================================
CREATE OR REPLACE PROCEDURE sp_devoluciones_lista_ventas()
BEGIN
    SELECT
        d.id_devolucion,
        d.id_pedido,
        d.fecha_devolucion,
        MIN(ed.estado_devolucion) AS estado_devolucion,
        MIN(td.tipo_devolucion) AS tipo_devolucion,
        COUNT(DISTINCT dd.id_devolucion_detalle) AS cantidad_productos,
        GROUP_CONCAT(DISTINCT ed.estado_devolucion) AS estados_disponibles
    FROM Devoluciones d
    LEFT JOIN Devoluciones_Detalles dd ON d.id_devolucion = dd.id_devolucion
    LEFT JOIN Estados_Devoluciones ed ON dd.id_estado_devolucion = ed.id_estado_devolucion
    LEFT JOIN Tipos_Devoluciones td ON dd.id_tipo_devoluciones = td.id_tipo_devoluciones
    GROUP BY d.id_devolucion, d.id_pedido, d.fecha_devolucion
    ORDER BY d.fecha_devolucion DESC, d.id_devolucion DESC;
END$$

-- =========================================
-- sp_devoluciones_por_anio
-- =========================================
CREATE OR REPLACE PROCEDURE sp_devoluciones_por_anio(
    IN p_anios_atras INT
)
BEGIN
    SELECT
        YEAR(d.fecha_devolucion) AS anio,
        COUNT(DISTINCT d.id_devolucion) AS cantidad_devoluciones,
        COUNT(dd.id_devolucion_detalle) AS cantidad_productos,
        COALESCE(SUM(dd.cantidad_devuelta * pr.precio_unitario), 0) AS total_devolucion
    FROM Devoluciones d
    JOIN Devoluciones_Detalles dd ON d.id_devolucion = dd.id_devolucion
    JOIN Pedidos_Detalles pd ON dd.id_pedido_detalle = pd.id_pedido_detalle
    JOIN Productos pr ON pd.id_producto = pr.id_producto
    WHERE YEAR(d.fecha_devolucion) >= YEAR(CURDATE()) - p_anios_atras
    GROUP BY YEAR(d.fecha_devolucion)
    ORDER BY anio ASC;
END$$

-- =========================================
-- sp_devoluciones_por_anio_todos
-- =========================================
CREATE OR REPLACE PROCEDURE sp_devoluciones_por_anio_todos(
    IN p_limit INT
)
BEGIN
    SELECT
        YEAR(d.fecha_devolucion) AS anio,
        COUNT(DISTINCT d.id_devolucion) AS cantidad_devoluciones,
        COUNT(dd.id_devolucion_detalle) AS cantidad_productos,
        COALESCE(SUM(dd.cantidad_devuelta * pr.precio_unitario), 0) AS total_devolucion
    FROM Devoluciones d
    JOIN Devoluciones_Detalles dd ON d.id_devolucion = dd.id_devolucion
    JOIN Pedidos_Detalles pd ON dd.id_pedido_detalle = pd.id_pedido_detalle
    JOIN Productos pr ON pd.id_producto = pr.id_producto
    GROUP BY YEAR(d.fecha_devolucion)
    ORDER BY anio DESC
    LIMIT p_limit;
END$$

-- =========================================
-- sp_devoluciones_recientes
-- =========================================
CREATE OR REPLACE PROCEDURE sp_devoluciones_recientes(
    IN p_limit INT
)
BEGIN
    SELECT
        d.id_devolucion,
        d.fecha_devolucion,
        COALESCE(MAX(ed.estado_devolucion), 'Pendiente') AS estado_devolucion,
        COUNT(DISTINCT dd.id_devolucion_detalle) AS cantidad_productos,
        COALESCE(SUM(dd.cantidad_devuelta * pr.precio_unitario), 0) AS total_devolucion
    FROM Devoluciones d
    LEFT JOIN Devoluciones_Detalles dd ON d.id_devolucion = dd.id_devolucion
    LEFT JOIN Estados_Devoluciones ed ON dd.id_estado_devolucion = ed.id_estado_devolucion
    LEFT JOIN Pedidos_Detalles pd ON dd.id_pedido_detalle = pd.id_pedido_detalle
    LEFT JOIN Productos pr ON pd.id_producto = pr.id_producto
    GROUP BY d.id_devolucion, d.fecha_devolucion
    ORDER BY d.fecha_devolucion DESC
    LIMIT p_limit;
END$$

-- =========================================
-- sp_devolucion_max_id
-- =========================================
CREATE OR REPLACE PROCEDURE sp_devolucion_max_id()
BEGIN
    SELECT MAX(id_devolucion) AS id_devolucion
    FROM Devoluciones;
END$$

-- =========================================
-- sp_empleados_lista
-- =========================================
CREATE OR REPLACE PROCEDURE sp_empleados_lista()
BEGIN
    SELECT DISTINCT
        u.id_usuario,
        u.nombre_usuario,
        u.nombre_primero,
        u.nombre_segundo,
        u.apellido_paterno,
        u.apellido_materno,
        u.correo,
        u.telefono,
        r.nombre_rol,
        s.nombre_sucursal,
        s.id_sucursal,
        ur.activo_usuario_rol,
        ur.fecha_asignacion
    FROM Usuarios u
    INNER JOIN Usuarios_Roles ur ON u.id_usuario = ur.id_usuario
    INNER JOIN Roles r ON ur.id_roles = r.id_roles
    LEFT JOIN Usuarios_Roles_Sucursales urs ON ur.id_usuario_rol_sucursal = urs.id_usuario_rol_sucursal
    LEFT JOIN Roles_Sucursales rs ON urs.id_roles_sucursal = rs.id_roles_sucursal
    LEFT JOIN Sucursales s ON rs.id_sucursal = s.id_sucursal
    WHERE r.nombre_rol <> 'Cliente'
    ORDER BY u.apellido_paterno, u.nombre_primero;
END$$

-- =========================================
-- sp_estados_direcciones_lista
-- =========================================
CREATE OR REPLACE PROCEDURE sp_estados_direcciones_lista()
BEGIN
    SELECT
        id_estado_direccion,
        estado_direccion
    FROM Estados_Direcciones
    ORDER BY estado_direccion;
END$$

-- =========================================
-- sp_facturacion_diaria_ayer
-- =========================================
CREATE OR REPLACE PROCEDURE sp_facturacion_diaria_ayer()
BEGIN
    SELECT *
    FROM TmpFacturacion
    WHERE DATE(fecha_reporte) = DATE_SUB(CURDATE(), INTERVAL 1 DAY);
END$$

-- =========================================
-- sp_facturacion_diaria_hoy
-- =========================================
CREATE OR REPLACE PROCEDURE sp_facturacion_diaria_hoy()
BEGIN
    SELECT *
    FROM TmpFacturacion
    WHERE DATE(fecha_reporte) = CURDATE();
END$$

-- =========================================
-- sp_facturacion_ordenada
-- =========================================
CREATE OR REPLACE PROCEDURE sp_facturacion_ordenada()
BEGIN
    SELECT *
    FROM TmpFacturacion
    ORDER BY fecha_reporte ASC;
END$$

-- =========================================
-- sp_facturas_con_pedidos_count
-- =========================================
CREATE OR REPLACE PROCEDURE sp_facturas_con_pedidos_count()
BEGIN
    SELECT COUNT(*) AS total
    FROM Facturas f
    INNER JOIN Pedidos p ON f.id_pedido = p.id_pedido;
END$$

DELIMITER ;


DELIMITER $$

-- =========================================
-- sp_facturas_count
-- =========================================
CREATE OR REPLACE PROCEDURE sp_facturas_count()
BEGIN
    SELECT COUNT(*) AS total
    FROM Facturas;
END$$

-- =========================================
-- sp_facturas_lista_filtrada
-- =========================================
CREATE OR REPLACE PROCEDURE sp_facturas_lista_filtrada(
    IN p_fecha_inicio DATE,
    IN p_fecha_fin    DATE
)
BEGIN
    SELECT
        f.id_factura,
        f.folio,
        f.id_pedido,
        f.fecha_emision,
        f.subtotal,
        f.impuestos,
        f.total,
        COALESCE(ef.estado_factura, 'Emitida') AS estado_factura,
        COALESCE(
            CONCAT(
                IFNULL(u.nombre_primero, ''),
                ' ',
                IFNULL(u.nombre_segundo, ''),
                ' ',
                IFNULL(u.apellido_paterno, ''),
                ' ',
                IFNULL(u.apellido_materno, '')
            ),
            'N/A'
        ) AS nombre_cliente,
        u.nombre_usuario,
        COALESCE(SUM(mp.monto_metodo_pago), 0) AS total_pagado,
        (f.total - COALESCE(SUM(mp.monto_metodo_pago), 0)) AS pendiente,
        CASE
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total THEN 'Pagada'
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) > 0 THEN 'Parcial'
            ELSE 'Pendiente'
        END AS estado_pago,
        p.fecha_pedido
    FROM Facturas f
    INNER JOIN Pedidos p ON f.id_pedido = p.id_pedido
    LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
    LEFT JOIN Usuarios u ON c.id_usuario = u.id_usuario
    LEFT JOIN Estados_Facturas ef ON f.id_factura = ef.id_factura
        AND ef.fecha_estado_factura = (
            SELECT MAX(ef2.fecha_estado_factura)
            FROM Estados_Facturas ef2
            WHERE ef2.id_factura = f.id_factura
        )
    LEFT JOIN Pagos pa ON f.id_factura = pa.id_factura
    LEFT JOIN Montos_Pagos mp ON pa.id_pago = mp.id_pago
    WHERE
        (p_fecha_inicio IS NULL OR f.fecha_emision >= p_fecha_inicio)
        AND (p_fecha_fin IS NULL OR f.fecha_emision <= p_fecha_fin)
    GROUP BY
        f.id_factura, f.folio, f.id_pedido, f.fecha_emision,
        f.subtotal, f.impuestos, f.total, ef.estado_factura,
        u.nombre_primero, u.nombre_segundo, u.apellido_paterno,
        u.apellido_materno, u.nombre_usuario, p.fecha_pedido
    ORDER BY f.fecha_emision DESC, f.id_factura DESC
    LIMIT 500;
END$$

-- =========================================
-- sp_facturas_pendientes
-- =========================================
CREATE OR REPLACE PROCEDURE sp_facturas_pendientes()
BEGIN
    SELECT
        f.id_factura,
        f.id_pedido,
        f.total,
        f.fecha_factura,
        COALESCE(SUM(mp.monto_metodo_pago), 0) AS total_pagado,
        (f.total - COALESCE(SUM(mp.monto_metodo_pago), 0)) AS pendiente,
        CASE
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total THEN 'Pagada'
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) > 0 THEN 'Parcial'
            ELSE 'Pendiente'
        END AS estado_pago
    FROM Facturas f
    LEFT JOIN Pagos p ON f.id_factura = p.id_factura
    LEFT JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
    GROUP BY f.id_factura, f.id_pedido, f.total, f.fecha_factura
    HAVING COALESCE(SUM(mp.monto_metodo_pago), 0) < f.total
    ORDER BY f.fecha_factura DESC;
END$$

-- =========================================
-- sp_factura_detalle_por_pedido
-- =========================================
CREATE OR REPLACE PROCEDURE sp_factura_detalle_por_pedido(
    IN p_id_pedido INT
)
BEGIN
    SELECT id_factura, total
    FROM Facturas
    WHERE id_pedido = p_id_pedido
    ORDER BY id_factura DESC
    LIMIT 1;
END$$

-- =========================================
-- sp_factura_por_pedido
-- (igual que el anterior, lo dejo separado porque asÃ­ lo tienes)
-- =========================================
CREATE OR REPLACE PROCEDURE sp_factura_por_pedido(
    IN p_id_pedido INT
)
BEGIN
    SELECT id_factura, total
    FROM Facturas
    WHERE id_pedido = p_id_pedido
    ORDER BY id_factura DESC
    LIMIT 1;
END$$

-- =========================================
-- sp_factura_total
-- =========================================
CREATE OR REPLACE PROCEDURE sp_factura_total(
    IN p_id_factura INT
)
BEGIN
    SELECT total
    FROM Facturas
    WHERE id_factura = p_id_factura;
END$$

-- =========================================
-- sp_generos_lista
-- =========================================
CREATE OR REPLACE PROCEDURE sp_generos_lista()
BEGIN
    SELECT id_genero, genero
    FROM Generos
    ORDER BY genero;
END$$

-- =========================================
-- sp_generos_productos_lista
-- =========================================
CREATE OR REPLACE PROCEDURE sp_generos_productos_lista()
BEGIN
    SELECT genero_producto
    FROM Generos_Productos
    ORDER BY genero_producto;
END$$

-- =========================================
-- sp_generos_productos_obtener_todos
-- =========================================
CREATE OR REPLACE PROCEDURE sp_generos_productos_obtener_todos()
BEGIN
    SELECT
        id_genero_producto,
        genero_producto
    FROM Generos_Productos
    ORDER BY genero_producto ASC;
END$$

-- =========================================
-- sp_ingresos_mes
-- =========================================
CREATE OR REPLACE PROCEDURE sp_ingresos_mes()
BEGIN
    SELECT SUM(total_facturado) AS ingresos_mes
    FROM TmpFacturacion;
END$$

-- =========================================
-- sp_ingresos_mes_anterior
-- (ojo: la lÃ³gica depende de cÃ³mo llenas TmpFacturacion)
-- =========================================
CREATE OR REPLACE PROCEDURE sp_ingresos_mes_anterior()
BEGIN
    SELECT SUM(total_facturado) AS ingresos_anterior
    FROM TmpFacturacion;
END$$

-- =========================================
-- sp_ingreso_total_modelo
-- =========================================
CREATE OR REPLACE PROCEDURE sp_ingreso_total_modelo(
    IN p_nombre_modelo VARCHAR(150)
)
BEGIN
    SELECT Ingreso_Total_Generado
    FROM vtopVentasMes
    WHERE Nombre_Modelo = p_nombre_modelo
    LIMIT 1;
END$$

-- =========================================
-- sp_inventario_bajo
-- =========================================
CREATE OR REPLACE PROCEDURE sp_inventario_bajo()
BEGIN
    SELECT *
    FROM vInventarioBajo
    LIMIT 20;
END$$

-- =========================================
-- sp_inventario_bajo_directo
-- =========================================
CREATE OR REPLACE PROCEDURE sp_inventario_bajo_directo()
BEGIN
    SELECT
        m.nombre_producto,
        s.sku,
        COALESCE(SUM(sp.stock_actual), 0) AS stock_actual,
        COALESCE(MAX(sp.stock_ideal), m.stock_minimo, 0) AS stock_minimo
    FROM Productos p
    JOIN Modelos m ON p.id_modelo = m.id_modelo
    JOIN Sku s ON p.id_sku = s.id_sku
    LEFT JOIN Sucursales_Productos sp ON p.id_producto = sp.id_producto
    WHERE m.activo = 1
      AND p.activo_producto = 1
    GROUP BY m.id_modelo, m.nombre_producto, s.sku, m.stock_minimo
    HAVING COALESCE(SUM(sp.stock_actual), 0) < COALESCE(MAX(sp.stock_ideal), m.stock_minimo, 0)
    ORDER BY stock_actual ASC
    LIMIT 20;
END$$

-- =========================================
-- sp_margen_por_categoria
-- =========================================
CREATE OR REPLACE PROCEDURE sp_margen_por_categoria()
BEGIN
    SELECT *
    FROM vMargenPorCategoria
    ORDER BY Ingreso_Total DESC;
END$$

-- =========================================
-- sp_margen_promedio
-- =========================================
CREATE OR REPLACE PROCEDURE sp_margen_promedio()
BEGIN
    SELECT AVG(Margen_Porcentaje) AS margen_promedio
    FROM vMargenPorCategoria;
END$$

-- =========================================
-- sp_materiales_lista
-- =========================================
CREATE OR REPLACE PROCEDURE sp_materiales_lista()
BEGIN
    SELECT material
    FROM Materiales
    ORDER BY material;
END$$

-- =========================================
-- sp_materiales_obtener_todos
-- =========================================
CREATE OR REPLACE PROCEDURE sp_materiales_obtener_todos()
BEGIN
    SELECT
        id_material,
        material
    FROM Materiales
    ORDER BY material ASC;
END$$

-- =========================================
-- sp_metodos_pago_lista
-- =========================================
CREATE OR REPLACE PROCEDURE sp_metodos_pago_lista()
BEGIN
    SELECT id_metodo_pago, nombre_metodo_pago
    FROM Metodos_Pagos
    ORDER BY id_metodo_pago;
END$$

-- =========================================
-- sp_metodos_pago_lista_nombre
-- =========================================
CREATE OR REPLACE PROCEDURE sp_metodos_pago_lista_nombre()
BEGIN
    SELECT id_metodo_pago, nombre_metodo_pago
    FROM Metodos_Pagos
    ORDER BY nombre_metodo_pago;
END$$

-- =========================================
-- sp_motivos_devolucion_lista
-- =========================================
CREATE OR REPLACE PROCEDURE sp_motivos_devolucion_lista()
BEGIN
    SELECT DISTINCT motivo_devolucion
    FROM Devoluciones_Detalles
    WHERE motivo_devolucion IS NOT NULL
      AND motivo_devolucion <> ''
    ORDER BY motivo_devolucion;
END$$

-- =========================================
-- sp_pedidos_completados
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedidos_completados()
BEGIN
    SELECT
        p.id_pedido,
        p.fecha_pedido,
        ep.estado_pedido
    FROM Pedidos p
    JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    WHERE ep.estado_pedido = 'Completado'
    ORDER BY p.fecha_pedido DESC;
END$$

-- =========================================
-- sp_pedidos_completados_view
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedidos_completados_view()
BEGIN
    SELECT *
    FROM vPedidosPorEstado
    WHERE estado_pedido = 'Completado';
END$$

-- =========================================
-- sp_pedidos_count_rango
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedidos_count_rango(
    IN p_fecha_desde DATE,
    IN p_fecha_hasta DATE
)
BEGIN
    SELECT COUNT(*) AS total_pedidos
    FROM Pedidos p
    WHERE DATE(p.fecha_pedido) BETWEEN p_fecha_desde AND p_fecha_hasta
      AND p.id_estado_pedido <> 4;
END$$

-- =========================================
-- sp_pedidos_para_devolucion
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedidos_para_devolucion()
BEGIN
    SELECT DISTINCT
        p.id_pedido,
        p.fecha_pedido
    FROM Pedidos p
    JOIN Pedidos_Detalles pd ON p.id_pedido = pd.id_pedido
    WHERE p.id_estado_pedido <> 4
    ORDER BY p.fecha_pedido DESC;
END$$

-- =========================================
-- sp_pedidos_para_devolucion_limitado
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedidos_para_devolucion_limitado(
    IN p_limit INT
)
BEGIN
    SELECT DISTINCT
        p.id_pedido,
        p.fecha_pedido
    FROM Pedidos p
    JOIN Pedidos_Detalles pd ON p.id_pedido = pd.id_pedido
    ORDER BY p.fecha_pedido DESC
    LIMIT p_limit;
END$$

-- =========================================
-- sp_pedidos_por_estado
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedidos_por_estado()
BEGIN
    SELECT *
    FROM vPedidosPorEstado;
END$$

-- =========================================
-- sp_pedidos_por_estado_filtrado
-- p_estados es algo tipo:  "'Confirmado','Completado'"
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedidos_por_estado_filtrado(
    IN p_estados TEXT
)
BEGIN
    SET @sql = CONCAT(
        'SELECT * FROM vPedidosPorEstado WHERE estado_pedido IN (',
        p_estados,
        ')'
    );
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END$$

-- =========================================
-- sp_pedido_max_id
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedido_max_id()
BEGIN
    SELECT MAX(id_pedido) AS id_pedido
    FROM Pedidos;
END$$

-- =========================================
-- sp_pedido_productos
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedido_productos(
    IN p_id_pedido INT
)
BEGIN
    SELECT
        pd.id_pedido_detalle,
        pd.id_producto,
        pd.cantidad_producto,
        m.nombre_producto,
        p.precio_unitario,
        s.sku
    FROM Pedidos_Detalles pd
    JOIN Productos p ON pd.id_producto = p.id_producto
    JOIN Modelos m ON p.id_modelo = m.id_modelo
    JOIN Sku s ON p.id_sku = s.id_sku
    WHERE pd.id_pedido = p_id_pedido;
END$$

DELIMITER ;

DELIMITER $$

-- =========================================
-- sp_productos_activos_pedido
-- =========================================
CREATE OR REPLACE PROCEDURE sp_productos_activos_pedido()
BEGIN
    SELECT
        p.id_producto,
        m.nombre_producto AS nombre,
        p.precio_unitario AS precio,
        s.sku,
        cat.nombre_categoria
    FROM Productos p
    JOIN Modelos m   ON p.id_modelo   = m.id_modelo
    JOIN Sku s       ON p.id_sku      = s.id_sku
    JOIN Categorias cat ON m.id_categoria = cat.id_categoria
    WHERE p.activo_producto = 1
    ORDER BY m.nombre_producto;
END$$

-- =========================================
-- sp_productos_catalogo_ventas
-- =========================================
CREATE OR REPLACE PROCEDURE sp_productos_catalogo_ventas(
    IN p_categoria VARCHAR(100)
)
BEGIN
    IF p_categoria IS NOT NULL AND p_categoria <> '' THEN
        SELECT
            p.id_producto,
            p.precio_unitario,
            p.descuento_producto,
            p.costo_unitario,
            p.activo_producto,
            m.nombre_producto,
            m.nombre_producto AS nombre,
            s.sku,
            c.nombre_categoria,
            c.id_categoria,
            mat.material,
            gp.genero_producto
        FROM Productos p
        INNER JOIN Modelos m          ON p.id_modelo          = m.id_modelo
        INNER JOIN Categorias c       ON m.id_categoria       = c.id_categoria
        INNER JOIN Sku s              ON p.id_sku             = s.id_sku
        INNER JOIN Materiales mat     ON p.id_material        = mat.id_material
        INNER JOIN Generos_Productos gp ON m.id_genero_producto = gp.id_genero_producto
        WHERE p.activo_producto = 1
          AND c.nombre_categoria = p_categoria
        ORDER BY m.nombre_producto;
    ELSE
        SELECT
            p.id_producto,
            p.precio_unitario,
            p.descuento_producto,
            p.costo_unitario,
            p.activo_producto,
            m.nombre_producto,
            m.nombre_producto AS nombre,
            s.sku,
            c.nombre_categoria,
            c.id_categoria,
            mat.material,
            gp.genero_producto
        FROM Productos p
        INNER JOIN Modelos m          ON p.id_modelo          = m.id_modelo
        INNER JOIN Categorias c       ON m.id_categoria       = c.id_categoria
        INNER JOIN Sku s              ON p.id_sku             = s.id_sku
        INNER JOIN Materiales mat     ON p.id_material        = mat.id_material
        INNER JOIN Generos_Productos gp ON m.id_genero_producto = gp.id_genero_producto
        WHERE p.activo_producto = 1
        ORDER BY m.nombre_producto;
    END IF;
END$$

-- =========================================
-- sp_productos_count
-- =========================================
CREATE OR REPLACE PROCEDURE sp_productos_count()
BEGIN
    SELECT COUNT(*) AS total
    FROM Productos;
END$$

-- =========================================
-- sp_productos_para_sucursal
-- =========================================
CREATE OR REPLACE PROCEDURE sp_productos_para_sucursal()
BEGIN
    SELECT
        p.id_producto,
        m.nombre_producto,
        s.sku
    FROM Productos p
    JOIN Modelos m ON p.id_modelo = m.id_modelo
    JOIN Sku s     ON p.id_sku    = s.id_sku
    WHERE p.activo_producto = 1
    ORDER BY m.nombre_producto;
END$$

-- =========================================
-- sp_producto_max_id
-- =========================================
CREATE OR REPLACE PROCEDURE sp_producto_max_id()
BEGIN
    SELECT MAX(id_producto) AS id_producto
    FROM Productos;
END$$

DELIMITER ;

DELIMITER $$

-- =====================================================
-- sp_roles_empleados
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_roles_empleados()
BEGIN
    SELECT id_roles, nombre_rol
    FROM Roles
    WHERE nombre_rol NOT IN ('Cliente', 'Admin')
    ORDER BY nombre_rol;
END$$

-- =====================================================
-- sp_sucursales_activas
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_sucursales_activas()
BEGIN
    SELECT id_sucursal, nombre_sucursal
    FROM Sucursales
    WHERE activo_sucursal = 1
    ORDER BY nombre_sucursal;
END$$

-- =====================================================
-- sp_sucursal_activa_primera
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_sucursal_activa_primera()
BEGIN
    SELECT nombre_sucursal, id_sucursal
    FROM Sucursales
    WHERE activo_sucursal = 1
    LIMIT 1;
END$$

-- =====================================================
-- sp_sucursal_actualizar_estado
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_sucursal_actualizar_estado(
    IN p_id_sucursal INT,
    IN p_activo TINYINT
)
BEGIN
    UPDATE Sucursales
    SET activo_sucursal = p_activo
    WHERE id_sucursal = p_id_sucursal;

    SELECT ROW_COUNT() AS filas_afectadas;
END$$

-- =====================================================
-- sp_tickets_promedio
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_tickets_promedio()
BEGIN
    SELECT * FROM vTicketsPromedio;
END$$

-- =====================================================
-- sp_tipos_devolucion_lista
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_tipos_devolucion_lista()
BEGIN
    SELECT id_tipo_devoluciones, tipo_devolucion
    FROM Tipos_Devoluciones
    ORDER BY tipo_devolucion;
END$$

-- =====================================================
-- sp_tmp_items_pedido_count
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_tmp_items_pedido_count(
    IN p_id_tmp_pedido INT
)
BEGIN
    SELECT COUNT(*) AS total
    FROM TmpItems_Pedido
    WHERE id_tmp_pedido = p_id_tmp_pedido;
END$$

-- =====================================================
-- sp_tmp_item_pedido_insertar
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_tmp_item_pedido_insertar(
    IN p_id_producto INT,
    IN p_cantidad INT,
    IN p_id_tmp_pedido INT
)
BEGIN
    INSERT INTO TmpItems_Pedido (id_producto, cantidad_producto, id_tmp_pedido)
    VALUES (p_id_producto, p_cantidad, p_id_tmp_pedido);

    SELECT ROW_COUNT() AS filas_afectadas;
END$$

-- =====================================================
-- sp_tmp_pedido_insertar
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_tmp_pedido_insertar(
    IN p_id_usuario INT
)
BEGIN
    INSERT INTO TmpPedidos (id_usuario)
    VALUES (p_id_usuario);

    SELECT LAST_INSERT_ID() AS id_tmp_pedido;
END$$

-- =====================================================
-- sp_top_clientes_gasto
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_top_clientes_gasto(
    IN p_fecha_desde DATE,
    IN p_fecha_hasta DATE,
    IN p_limit INT
)
BEGIN
    SELECT
        CONCAT(
            u.nombre_primero, ' ',
            IFNULL(u.nombre_segundo, ''), ' ',
            u.apellido_paterno, ' ',
            IFNULL(u.apellido_materno, '')
        ) AS nombre_completo,
        u.nombre_usuario,
        COUNT(DISTINCT p.id_pedido) AS total_pedidos,
        SUM(
            COALESCE(
                (SELECT SUM(pd.cantidad_producto * pr.precio_unitario)
                 FROM Pedidos_Detalles pd
                 JOIN Productos pr ON pd.id_producto = pr.id_producto
                 WHERE pd.id_pedido = p.id_pedido), 0
            )
        ) AS total_gastado
    FROM Pedidos p
    JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    JOIN Clientes c ON pc.id_cliente = c.id_cliente
    JOIN Usuarios u ON c.id_usuario = u.id_usuario
    WHERE DATE(p.fecha_pedido) BETWEEN p_fecha_desde AND p_fecha_hasta
      AND p.id_estado_pedido <> 4
    GROUP BY u.id_usuario, u.nombre_primero, u.nombre_segundo,
             u.apellido_paterno, u.apellido_materno, u.nombre_usuario
    ORDER BY total_gastado DESC, total_pedidos DESC
    LIMIT p_limit;
END$$

-- =====================================================
-- sp_top_clientes_pedidos
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_top_clientes_pedidos(
    IN p_fecha_desde DATE,
    IN p_fecha_hasta DATE
)
BEGIN
    SELECT
        CONCAT(
            u.nombre_primero, ' ',
            IFNULL(u.nombre_segundo, ''), ' ',
            u.apellido_paterno, ' ',
            IFNULL(u.apellido_materno, '')
        ) AS nombre_completo,
        u.nombre_usuario,
        COUNT(DISTINCT p.id_pedido) AS total_pedidos,
        SUM(
            COALESCE(
                (SELECT SUM(pd.cantidad_producto * pr.precio_unitario)
                 FROM Pedidos_Detalles pd
                 JOIN Productos pr ON pd.id_producto = pr.id_producto
                 WHERE pd.id_pedido = p.id_pedido), 0
            )
        ) AS total_gastado
    FROM Pedidos p
    JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    JOIN Clientes c ON pc.id_cliente = c.id_cliente
    JOIN Usuarios u ON c.id_usuario = u.id_usuario
    WHERE DATE(p.fecha_pedido) BETWEEN p_fecha_desde AND p_fecha_hasta
      AND p.id_estado_pedido <> 4
    GROUP BY u.id_usuario, u.nombre_primero, u.nombre_segundo,
             u.apellido_paterno, u.apellido_materno, u.nombre_usuario
    ORDER BY total_pedidos DESC, total_gastado DESC;
END$$

DELIMITER ;
DELIMITER $$

-- =====================================================
-- sp_top_productos
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_top_productos(
    IN var_fecha_desde DATE,
    IN var_fecha_hasta DATE,
    IN var_n INT
)
BEGIN
    CREATE TEMPORARY TABLE IF NOT EXISTS TmpTop_Productos (
        top INT PRIMARY KEY AUTO_INCREMENT,
        nombre VARCHAR(150) NOT NULL,
        cantidad_vendida INT NOT NULL
    );

    TRUNCATE TABLE TmpTop_Productos;

    INSERT INTO TmpTop_Productos (nombre, cantidad_vendida)
    SELECT
        m.nombre_producto,
        SUM(pd.cantidad_producto) AS total_vendido
    FROM Pedidos pe
    JOIN Pedidos_Detalles pd ON pe.id_pedido = pd.id_pedido
    JOIN Productos p ON pd.id_producto = p.id_producto
    JOIN Modelos m ON p.id_modelo = m.id_modelo
    WHERE
        (var_fecha_desde IS NULL OR DATE(pe.fecha_pedido) >= var_fecha_desde)
        AND (var_fecha_hasta IS NULL OR DATE(pe.fecha_pedido) <= var_fecha_hasta)
        AND pe.id_estado_pedido <> 4
    GROUP BY m.nombre_producto
    ORDER BY total_vendido DESC
    LIMIT var_n;

    SELECT * FROM TmpTop_Productos;
END$$

-- =====================================================
-- sp_top_productos_tmp
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_top_productos_tmp(IN p_limit INT)
BEGIN
    SELECT *
    FROM TmpTop_Productos
    ORDER BY top
    LIMIT p_limit;
END$$

-- =====================================================
-- sp_top_productos_vendidos
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_top_productos_vendidos(
    IN p_fecha_desde DATE,
    IN p_fecha_hasta DATE,
    IN p_limit INT
)
BEGIN
    SELECT
        m.nombre_producto,
        s.sku,
        SUM(pd.cantidad_producto) AS unidades_vendidas,
        SUM(pd.cantidad_producto * p.precio_unitario) AS ingresos_totales,
        AVG(p.precio_unitario) AS precio_promedio
    FROM Pedidos pe
    JOIN Pedidos_Detalles pd ON pe.id_pedido = pd.id_pedido
    JOIN Productos p ON pd.id_producto = p.id_producto
    JOIN Modelos m ON p.id_modelo = m.id_modelo
    JOIN Sku s ON p.id_sku = s.id_sku
    WHERE DATE(pe.fecha_pedido) BETWEEN p_fecha_desde AND p_fecha_hasta
      AND pe.id_estado_pedido <> 4
    GROUP BY m.id_modelo, m.nombre_producto, s.sku
    ORDER BY ingresos_totales DESC
    LIMIT p_limit;
END$$

-- =====================================================
-- sp_usuarios_activos_count
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_usuarios_activos_count()
BEGIN
    SELECT COUNT(*) AS activos
    FROM Usuarios
    WHERE activo_usuario = 1;
END$$

-- =====================================================
-- sp_usuario_datos
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_usuario_datos(IN p_id_usuario INT)
BEGIN
    SELECT
        u.id_usuario,
        u.rfc_usuario,
        u.id_direccion,
        u.telefono,
        c.id_cliente
    FROM Usuarios u
    LEFT JOIN Clientes c ON c.id_usuario = u.id_usuario
    WHERE u.id_usuario = p_id_usuario;
END$$

-- =====================================================
-- sp_usuario_datos_completos
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_usuario_datos_completos(IN p_id_usuario INT)
BEGIN
    SELECT
        u.nombre_usuario,
        u.nombre_primero,
        u.nombre_segundo,
        u.apellido_paterno,
        u.apellido_materno,
        u.correo,
        u.telefono,
        u.rfc_usuario,
        u.id_direccion,
        c.id_cliente
    FROM Usuarios u
    LEFT JOIN Clientes c ON c.id_usuario = u.id_usuario
    WHERE u.id_usuario = p_id_usuario;
END$$

-- =====================================================
-- sp_usuario_obtener_contrasena
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_usuario_obtener_contrasena(IN p_id_usuario INT)
BEGIN
    SELECT contrasena
    FROM Usuarios
    WHERE id_usuario = p_id_usuario;
END$$

-- =====================================================
-- sp_usuario_obtener_rol_por_username
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_usuario_obtener_rol_por_username(IN p_username VARCHAR(50))
BEGIN
    SELECT
        u.id_usuario,
        CONCAT(
            u.nombre_primero, ' ',
            IFNULL(u.nombre_segundo, ''), ' ',
            u.apellido_paterno, ' ',
            IFNULL(u.apellido_materno, '')
        ) AS nombre_completo,
        u.nombre_usuario,
        u.contrasena,
        r.nombre_rol,
        ur.id_usuario_rol
    FROM Usuarios u
    INNER JOIN Usuarios_Roles ur ON ur.id_usuario = u.id_usuario
    INNER JOIN Roles r ON r.id_roles = ur.id_roles
    WHERE u.nombre_usuario = p_username
      AND ur.activo_usuario_rol = 1
    ORDER BY ur.fecha_asignacion DESC
    LIMIT 1;
END$$

-- =====================================================
-- sp_usuario_rol_inventario
-- =====================================================
CREATE OR REPLACE PROCEDURE sp_usuario_rol_inventario(IN p_id_usuario INT)
BEGIN
    SELECT ur.id_usuario_rol
    FROM Usuarios_Roles ur
    JOIN Roles r ON ur.id_roles = r.id_roles
    WHERE ur.id_usuario = p_id_usuario
      AND r.nombre_rol = 'inventario'
      AND ur.activo_usuario_rol = 1
    LIMIT 1;
END$$

DELIMITER ;
DELIMITER $$

-- =========================================
-- sp_usuario_rol_obtener
-- =========================================
CREATE OR REPLACE PROCEDURE sp_usuario_rol_obtener(
    IN p_id_usuario INT,
    IN p_nombre_rol VARCHAR(50)
)
BEGIN
    SELECT ur.id_usuario_rol
    FROM Usuarios_Roles ur
    JOIN Roles r ON ur.id_roles = r.id_roles
    WHERE ur.id_usuario = p_id_usuario
      AND r.nombre_rol = p_nombre_rol
      AND ur.activo_usuario_rol = 1
    LIMIT 1;
END$$

-- =========================================
-- sp_usuario_rol_primero_activo
-- =========================================
CREATE OR REPLACE PROCEDURE sp_usuario_rol_primero_activo(
    IN p_id_usuario INT
)
BEGIN
    SELECT id_usuario_rol
    FROM Usuarios_Roles
    WHERE id_usuario = p_id_usuario
      AND activo_usuario_rol = 1
    LIMIT 1;
END$$

-- =========================================
-- sp_usuario_sucursal
-- =========================================
CREATE OR REPLACE PROCEDURE sp_usuario_sucursal(
    IN p_id_usuario INT
)
BEGIN
    SELECT
        s.nombre_sucursal,
        s.id_sucursal
    FROM Usuarios_Roles_Sucursales urs
    JOIN Roles_Sucursales rs ON urs.id_roles_sucursal = rs.id_roles_sucursal
    JOIN Sucursales s ON rs.id_sucursal = s.id_sucursal
    WHERE urs.id_usuario = p_id_usuario
      AND urs.activo_usuario_rol_sucursal = 1
      AND s.activo_sucursal = 1
    LIMIT 1;
END$$

-- =========================================
-- sp_usuario_sucursal_por_rol
-- =========================================
CREATE OR REPLACE PROCEDURE sp_usuario_sucursal_por_rol(
    IN p_id_usuario INT,
    IN p_nombre_rol VARCHAR(50)
)
BEGIN
    SELECT
        s.nombre_sucursal,
        s.id_sucursal
    FROM Usuarios_Roles_Sucursales urs
    JOIN Roles_Sucursales rs ON urs.id_roles_sucursal = rs.id_roles_sucursal
    JOIN Roles r ON rs.id_roles = r.id_roles
    JOIN Sucursales s ON rs.id_sucursal = s.id_sucursal
    WHERE urs.id_usuario = p_id_usuario
      AND r.nombre_rol = p_nombre_rol
      AND urs.activo_usuario_rol_sucursal = 1
      AND s.activo_sucursal = 1
    LIMIT 1;
END$$

DELIMITER ;

DELIMITER $$

-- =========================================
-- sp_ventas_mes_total
-- =========================================
CREATE OR REPLACE PROCEDURE sp_ventas_mes_total()
BEGIN
    SELECT SUM(total_facturado) AS ventas_mes
    FROM TmpFacturacion;
END$$

-- =========================================
-- sp_ventas_por_anio
-- =========================================
CREATE OR REPLACE PROCEDURE sp_ventas_por_anio(
    IN p_anios_atras INT
)
BEGIN
    SELECT
        YEAR(p.fecha_pedido) AS anio,
        COALESCE(SUM(pd.cantidad_producto * pr.precio_unitario), 0) AS total_anio,
        COUNT(DISTINCT p.id_pedido) AS pedidos_anio
    FROM Pedidos p
    JOIN Pedidos_Detalles pd ON p.id_pedido = pd.id_pedido
    JOIN Productos pr ON pd.id_producto = pr.id_producto
    WHERE p.id_estado_pedido <> 4
      AND YEAR(p.fecha_pedido) >= YEAR(CURDATE()) - p_anios_atras
    GROUP BY YEAR(p.fecha_pedido)
    ORDER BY anio ASC;
END$$

-- =========================================
-- sp_ventas_por_anio_todos
-- =========================================
CREATE OR REPLACE PROCEDURE sp_ventas_por_anio_todos(
    IN p_limit INT
)
BEGIN
    SELECT
        YEAR(p.fecha_pedido) AS anio,
        COALESCE(SUM(pd.cantidad_producto * pr.precio_unitario), 0) AS total_anio,
        COUNT(DISTINCT p.id_pedido) AS pedidos_anio
    FROM Pedidos p
    JOIN Pedidos_Detalles pd ON p.id_pedido = pd.id_pedido
    JOIN Productos pr ON pd.id_producto = pr.id_producto
    WHERE p.id_estado_pedido <> 4
    GROUP BY YEAR(p.fecha_pedido)
    ORDER BY anio DESC
    LIMIT p_limit;
END$$

-- =========================================
-- sucursalActualizar
-- =========================================
CREATE OR REPLACE PROCEDURE sucursalActualizar(
    IN p_id_sucursal INT,
    IN p_nombre_sucursal VARCHAR(150),
    IN p_codigo_postal VARCHAR(10),
    IN p_id_estado INT,
    IN p_municipio VARCHAR(150),
    IN p_calle_direccion VARCHAR(150),
    IN p_numero_direccion VARCHAR(50),
    IN p_activo_sucursal TINYINT
)
BEGIN
    DECLARE v_id_cp INT;
    DECLARE v_id_direccion INT;
    DECLARE v_id_municipio INT;
    DECLARE v_mensaje VARCHAR(500);

    IF NOT EXISTS (SELECT 1 FROM Sucursales WHERE id_sucursal = p_id_sucursal) THEN
        SET v_mensaje = 'La sucursal no existe';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF TRIM(p_nombre_sucursal) = '' THEN
        SET v_mensaje = 'El nombre de la sucursal es requerido';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Sucursales
        WHERE nombre_sucursal = TRIM(p_nombre_sucursal)
          AND id_sucursal != p_id_sucursal
    ) THEN
        SET v_mensaje = CONCAT('Ya existe otra sucursal con el nombre: ', TRIM(p_nombre_sucursal));
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF TRIM(p_codigo_postal) = '' THEN
        SET v_mensaje = 'El cÃ³digo postal es requerido';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    SELECT id_direccion INTO v_id_direccion
    FROM Sucursales
    WHERE id_sucursal = p_id_sucursal;

    SELECT id_cp INTO v_id_cp
    FROM Codigos_Postales
    WHERE codigo_postal = TRIM(p_codigo_postal)
    LIMIT 1;

    IF v_id_cp IS NULL THEN
        INSERT INTO Codigos_Postales (codigo_postal)
        VALUES (TRIM(p_codigo_postal));
        SET v_id_cp = LAST_INSERT_ID();
    END IF;

    IF p_id_estado IS NOT NULL THEN
        INSERT IGNORE INTO Codigos_Postales_Estados (id_cp, id_estado_direccion)
        VALUES (v_id_cp, p_id_estado);
    END IF;

    IF p_municipio IS NOT NULL AND TRIM(p_municipio) <> '' THEN
        SELECT id_municipio_direccion INTO v_id_municipio
        FROM Municipios_Direcciones
        WHERE municipio_direccion = TRIM(p_municipio)
        LIMIT 1;

        IF v_id_municipio IS NULL THEN
            INSERT INTO Municipios_Direcciones (municipio_direccion)
            VALUES (TRIM(p_municipio));
            SET v_id_municipio = LAST_INSERT_ID();
        END IF;

        INSERT IGNORE INTO Codigos_Postales_Municipios (id_cp, id_municipio_direccion)
        VALUES (v_id_cp, v_id_municipio);
    END IF;

    UPDATE Direcciones
    SET calle_direccion = TRIM(p_calle_direccion),
        numero_direccion = TRIM(p_numero_direccion),
        id_cp = v_id_cp
    WHERE id_direccion = v_id_direccion;

    UPDATE Sucursales
    SET nombre_sucursal = TRIM(p_nombre_sucursal),
        activo_sucursal = p_activo_sucursal
    WHERE id_sucursal = p_id_sucursal;

    SELECT 'Sucursal actualizada exitosamente' AS Mensaje;
END$$

-- =========================================
-- sucursalCrear
-- =========================================
CREATE OR REPLACE PROCEDURE sucursalCrear(
    IN p_nombre_sucursal VARCHAR(150),
    IN p_codigo_postal VARCHAR(10),
    IN p_id_estado INT,
    IN p_municipio VARCHAR(150),
    IN p_calle_direccion VARCHAR(150),
    IN p_numero_direccion VARCHAR(50),
    IN p_activo_sucursal TINYINT
)
BEGIN
    DECLARE v_id_cp INT;
    DECLARE v_id_direccion INT;
    DECLARE v_id_sucursal INT;
    DECLARE v_id_municipio INT;
    DECLARE v_mensaje VARCHAR(500);

    IF TRIM(p_nombre_sucursal) = '' THEN
        SET v_mensaje = 'El nombre de la sucursal es requerido';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Sucursales
        WHERE nombre_sucursal = TRIM(p_nombre_sucursal)
    ) THEN
        SET v_mensaje = CONCAT('Ya existe una sucursal con el nombre: ', TRIM(p_nombre_sucursal));
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF TRIM(p_codigo_postal) = '' THEN
        SET v_mensaje = 'El cÃ³digo postal es requerido';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    SELECT id_cp INTO v_id_cp
    FROM Codigos_Postales
    WHERE codigo_postal = TRIM(p_codigo_postal)
    LIMIT 1;

    IF v_id_cp IS NULL THEN
        INSERT INTO Codigos_Postales (codigo_postal)
        VALUES (TRIM(p_codigo_postal));
        SET v_id_cp = LAST_INSERT_ID();
    END IF;

    IF p_id_estado IS NOT NULL THEN
        INSERT IGNORE INTO Codigos_Postales_Estados (id_cp, id_estado_direccion)
        VALUES (v_id_cp, p_id_estado);
    END IF;

    IF p_municipio IS NOT NULL AND TRIM(p_municipio) <> '' THEN
        SELECT id_municipio_direccion INTO v_id_municipio
        FROM Municipios_Direcciones
        WHERE municipio_direccion = TRIM(p_municipio)
        LIMIT 1;

        IF v_id_municipio IS NULL THEN
            INSERT INTO Municipios_Direcciones (municipio_direccion)
            VALUES (TRIM(p_municipio));
            SET v_id_municipio = LAST_INSERT_ID();
        END IF;

        INSERT IGNORE INTO Codigos_Postales_Municipios (id_cp, id_municipio_direccion)
        VALUES (v_id_cp, v_id_municipio);
    END IF;

    INSERT INTO Direcciones (calle_direccion, numero_direccion, id_cp)
    VALUES (TRIM(p_calle_direccion), TRIM(p_numero_direccion), v_id_cp);

    SET v_id_direccion = LAST_INSERT_ID();

    INSERT INTO Sucursales (nombre_sucursal, id_direccion, activo_sucursal)
    VALUES (TRIM(p_nombre_sucursal), v_id_direccion, p_activo_sucursal);

    SET v_id_sucursal = LAST_INSERT_ID();

    SELECT v_id_sucursal AS id_sucursal_creada;
END$$

-- =========================================
-- sucursalProductoAsignar
-- =========================================
CREATE OR REPLACE PROCEDURE sucursalProductoAsignar(
    IN p_id_sucursal INT,
    IN p_id_producto INT,
    IN p_stock_ideal INT,
    IN p_stock_actual INT,
    IN p_stock_maximo INT
)
BEGIN
    DECLARE v_mensaje VARCHAR(500);
    DECLARE v_existe INT;

    IF NOT EXISTS (SELECT 1 FROM Sucursales WHERE id_sucursal = p_id_sucursal AND activo_sucursal = 1) THEN
        SET v_mensaje = 'La sucursal no existe o estÃ¡ inactiva';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM Productos WHERE id_producto = p_id_producto AND activo_producto = 1) THEN
        SET v_mensaje = 'El producto no existe o estÃ¡ inactivo';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF p_stock_ideal < 0 THEN
        SET v_mensaje = 'El stock ideal no puede ser negativo';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF p_stock_actual < 0 THEN
        SET v_mensaje = 'El stock actual no puede ser negativo';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF p_stock_maximo < p_stock_ideal THEN
        SET v_mensaje = 'El stock mÃ¡ximo debe ser mayor o igual al stock ideal';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF p_stock_actual > p_stock_maximo THEN
        SET v_mensaje = CONCAT(
            'El stock actual (', p_stock_actual,
            ') no puede exceder el stock mÃ¡ximo (', p_stock_maximo, ')'
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    SELECT COUNT(*)
    INTO v_existe
    FROM Sucursales_Productos
    WHERE id_sucursal = p_id_sucursal
      AND id_producto = p_id_producto;

    IF v_existe > 0 THEN
        UPDATE Sucursales_Productos
        SET stock_ideal = p_stock_ideal,
            stock_actual = p_stock_actual,
            stock_maximo = p_stock_maximo
        WHERE id_sucursal = p_id_sucursal
          AND id_producto = p_id_producto;

        SELECT 'Producto actualizado en sucursal exitosamente' AS Mensaje;
    ELSE
        INSERT INTO Sucursales_Productos (
            id_sucursal, id_producto, stock_ideal, stock_actual, stock_maximo
        ) VALUES (
            p_id_sucursal, p_id_producto, p_stock_ideal, p_stock_actual, p_stock_maximo
        );

        SELECT 'Producto asignado a sucursal exitosamente' AS Mensaje;
    END IF;
END$$

-- =========================================
-- tiposMotivosDevolucion
-- =========================================
CREATE OR REPLACE PROCEDURE tiposMotivosDevolucion()
BEGIN
    SELECT
        id_tipo_devoluciones,
        tipo_devolucion
    FROM Tipos_Devoluciones
    ORDER BY id_tipo_devoluciones;

    SELECT
        'Talla incorrecta' AS motivo_devolucion
    UNION ALL SELECT 'Producto diferente al solicitado'
    UNION ALL SELECT 'No era lo esperado'
    UNION ALL SELECT 'DaÃ±o en empaque'
    UNION ALL SELECT 'Color distinto al mostrado'
    UNION ALL SELECT 'Cliente cambiÃ³ de opiniÃ³n'
    UNION ALL SELECT 'Defecto visual'
    UNION ALL SELECT 'No coincide con la fotografÃ­a'
    UNION ALL SELECT 'DaÃ±o en transporte'
    UNION ALL SELECT 'Regalo repetido'
    UNION ALL SELECT 'Otro'
    ORDER BY motivo_devolucion;
END$$

-- =========================================
-- ventas_estados_pedidos
-- =========================================
CREATE OR REPLACE PROCEDURE ventas_estados_pedidos()
BEGIN
    SELECT
        id_estado_pedido,
        estado_pedido
    FROM Estados_Pedidos
    WHERE estado_pedido IN ('Confirmado', 'Procesado', 'Completado', 'Cancelado')
    ORDER BY
        CASE estado_pedido
            WHEN 'Confirmado' THEN 1
            WHEN 'Procesado' THEN 2
            WHEN 'Completado' THEN 3
            WHEN 'Cancelado' THEN 4
            ELSE 5
        END;
END$$

-- =========================================
-- ventas_pedidos_lista
-- =========================================
CREATE OR REPLACE PROCEDURE ventas_pedidos_lista(
    IN p_fecha_filtro DATE,
    IN p_orden_fecha VARCHAR(10)
)
BEGIN
    SELECT
        p.id_pedido,
        p.fecha_pedido,
        COALESCE((
            SELECT SUM(pd.cantidad_producto * pr.precio_unitario)
            FROM Pedidos_Detalles pd
            JOIN Productos pr ON pd.id_producto = pr.id_producto
            WHERE pd.id_pedido = p.id_pedido
        ), 0) AS total_pedido,
        ep.estado_pedido,
        ep.id_estado_pedido,
        CONCAT(
            u.nombre_primero, ' ',
            IFNULL(u.nombre_segundo, ''), ' ',
            u.apellido_paterno, ' ',
            IFNULL(u.apellido_materno, '')
        ) AS nombre_cliente,
        u.nombre_usuario
    FROM Pedidos p
    LEFT JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    LEFT JOIN Clientes cl ON pc.id_cliente = cl.id_cliente
    LEFT JOIN Usuarios u ON cl.id_usuario = u.id_usuario
    WHERE
        (p_fecha_filtro IS NULL OR DATE(p.fecha_pedido) = p_fecha_filtro)
    ORDER BY
        CASE WHEN p_orden_fecha = 'ASC' THEN p.fecha_pedido END ASC,
        CASE WHEN p_orden_fecha = 'DESC' OR p_orden_fecha IS NULL THEN p.fecha_pedido END DESC
    LIMIT 100;
END$$

DELIMITER ;

-- =========================================
-- STORED PROCEDURES PARA SQL EMBEBIDO EN APP.PY
-- Este archivo contiene stored procedures que reemplazan
-- consultas SQL embebidas en app.py
-- =========================================

DELIMITER $$

-- =========================================
-- sp_factura_actualizar_total_descuento
-- Actualiza el total de una factura aplicando descuento de clasificación
-- =========================================
CREATE OR REPLACE PROCEDURE sp_factura_actualizar_total_descuento(
    IN p_id_factura INT,
    IN p_total DECIMAL(10,2)
)
BEGIN
    DECLARE v_subtotal DECIMAL(10,2);
    DECLARE v_impuestos DECIMAL(10,2);
    
    SET v_subtotal = p_total / 1.16;
    SET v_impuestos = p_total - v_subtotal;
    
    UPDATE Facturas 
    SET total = p_total,
        subtotal = v_subtotal,
        impuestos = v_impuestos
    WHERE id_factura = p_id_factura;
END$$

-- =========================================
-- sp_facturas_con_pedidos_count
-- Cuenta facturas que tienen pedidos asociados
-- =========================================
CREATE OR REPLACE PROCEDURE sp_facturas_con_pedidos_count()
BEGIN
    SELECT COUNT(*) as total 
    FROM Facturas f 
    INNER JOIN Pedidos p ON f.id_pedido = p.id_pedido;
END$$

-- =========================================
-- sp_routine_exists
-- Verifica si existe un stored procedure
-- =========================================
CREATE OR REPLACE PROCEDURE sp_routine_exists(
    IN p_routine_name VARCHAR(255)
)
BEGIN
    SELECT ROUTINE_NAME 
    FROM information_schema.ROUTINES 
    WHERE ROUTINE_SCHEMA = DATABASE() 
    AND ROUTINE_NAME = p_routine_name;
END$$

-- =========================================
-- sp_pedido_estado_obtener
-- Obtiene el estado de un pedido
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedido_estado_obtener(
    IN p_id_pedido INT
)
BEGIN
    SELECT ep.estado_pedido, ep.id_estado_pedido
    FROM Pedidos p
    JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    WHERE p.id_pedido = p_id_pedido;
END$$

-- =========================================
-- sp_pedido_estado_simple
-- Obtiene solo el estado de un pedido (sin id)
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedido_estado_simple(
    IN p_id_pedido INT
)
BEGIN
    SELECT ep.estado_pedido
    FROM Pedidos p
    JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    WHERE p.id_pedido = p_id_pedido;
END$$

-- =========================================
-- sp_facturacion_diaria_vista
-- Obtiene facturación diaria desde la vista
-- =========================================
CREATE OR REPLACE PROCEDURE sp_facturacion_diaria_vista(
    IN p_fecha_desde DATE,
    IN p_fecha_hasta DATE
)
BEGIN
    SELECT 
        Dia,
        Numero_Facturas,
        Subtotal_Diario,
        Impuestos_Diarios,
        Total_Facturado_Diario
    FROM vFacturacionDiaria
    WHERE Dia >= p_fecha_desde AND Dia <= p_fecha_hasta
    ORDER BY Dia ASC;
END$$

-- =========================================
-- sp_cobrado_por_mes
-- Obtiene cobrado agrupado por mes
-- =========================================
CREATE OR REPLACE PROCEDURE sp_cobrado_por_mes(
    IN p_fecha_desde DATE,
    IN p_fecha_hasta DATE
)
BEGIN
    SELECT 
        DATE_FORMAT(p.fecha_pago, '%Y-%m') as mes,
        SUM(mp.monto_metodo_pago) as cobrado
    FROM Pagos p
    JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
    WHERE p.fecha_pago >= p_fecha_desde AND p.fecha_pago <= p_fecha_hasta
    GROUP BY DATE_FORMAT(p.fecha_pago, '%Y-%m')
    ORDER BY mes ASC;
END$$

-- =========================================
-- sp_auditor_devoluciones_motivo
-- Obtiene devoluciones agrupadas por motivo
-- =========================================
CREATE OR REPLACE PROCEDURE sp_auditor_devoluciones_motivo()
BEGIN
    SELECT 
        COALESCE(dd.motivo_devolucion, 'Sin motivo') as motivo,
        COUNT(*) as cantidad
    FROM Devoluciones_Detalles dd
    GROUP BY dd.motivo_devolucion
    ORDER BY cantidad DESC
    LIMIT 10;
END$$

-- =========================================
-- sp_auditor_actividad_inventario_stock
-- Obtiene productos con stock bajo para auditoría
-- =========================================
CREATE OR REPLACE PROCEDURE sp_auditor_actividad_inventario_stock()
BEGIN
    SELECT COUNT(*) as bajo_stock
    FROM Sucursales_Productos sp
    JOIN Modelos m ON sp.id_modelo = m.id_modelo
    WHERE sp.stock_actual < m.stock_minimo;
END$$

-- =========================================
-- sp_auditor_actividad_ventas_estados
-- Obtiene conteo de pedidos por estado para auditoría
-- =========================================
CREATE OR REPLACE PROCEDURE sp_auditor_actividad_ventas_estados()
BEGIN
    SELECT 
        COUNT(CASE WHEN estado_pedido = 'Completado' THEN 1 END) as conformes,
        COUNT(CASE WHEN estado_pedido = 'Cancelado' THEN 1 END) as discrepancias
    FROM Pedidos;
END$$

-- =========================================
-- sp_auditor_actividad_facturas_pagadas
-- Obtiene conteo de facturas pagadas vs pendientes
-- =========================================
CREATE OR REPLACE PROCEDURE sp_auditor_actividad_facturas_pagadas()
BEGIN
    SELECT 
        COUNT(DISTINCT f.id_factura) as total,
        COUNT(DISTINCT CASE 
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total 
            THEN f.id_factura 
        END) as pagadas
    FROM Facturas f
    LEFT JOIN Pagos p ON f.id_factura = p.id_factura
    LEFT JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
    GROUP BY f.id_factura, f.total;
END$$

-- =========================================
-- sp_auditor_registros_recientes_pedidos
-- Obtiene pedidos recientes para auditoría
-- =========================================
CREATE OR REPLACE PROCEDURE sp_auditor_registros_recientes_pedidos()
BEGIN
    SELECT 
        'Pedido' as tipo,
        id_pedido as id_registro,
        fecha_pedido as fecha,
        'Nuevo' as estado_inicial,
        estado_pedido as estado_final,
        CASE 
            WHEN estado_pedido = 'Cancelado' THEN 'Discrepancia'
            ELSE 'Conforme'
        END as estado
    FROM Pedidos
    ORDER BY fecha_pedido DESC
    LIMIT 10;
END$$

-- =========================================
-- sp_auditor_registros_recientes_facturas
-- Obtiene facturas recientes para auditoría
-- =========================================
CREATE OR REPLACE PROCEDURE sp_auditor_registros_recientes_facturas()
BEGIN
    SELECT 
        'Factura' as tipo,
        id_factura as id_registro,
        fecha_emision as fecha,
        'Emitida' as estado_inicial,
        COALESCE(ef.estado_factura, 'Emitida') as estado_final,
        'Conforme' as estado
    FROM Facturas f
    LEFT JOIN Estados_Facturas ef ON f.id_factura = ef.id_factura
        AND ef.fecha_estado_factura = (
            SELECT MAX(ef2.fecha_estado_factura)
            FROM Estados_Facturas ef2
            WHERE ef2.id_factura = f.id_factura
        )
    ORDER BY fecha_emision DESC
    LIMIT 10;
END$$

-- =========================================
-- sp_productos_lista_completa_admin
-- Obtiene lista completa de productos para admin
-- =========================================
CREATE OR REPLACE PROCEDURE sp_productos_lista_completa_admin()
BEGIN
    SELECT 
        p.id_producto,
        p.precio_unitario,
        p.descuento_producto,
        p.costo_unitario,
        p.activo_producto,
        m.nombre_producto,
        m.id_modelo,
        c.nombre_categoria,
        c.id_categoria,
        s.sku,
        mat.material,
        gp.genero_producto,
        tp.talla,
        pok.kilataje,
        ppl.ley
    FROM Productos p
    JOIN Modelos m ON p.id_modelo = m.id_modelo
    JOIN Categorias c ON m.id_categoria = c.id_categoria
    JOIN Sku s ON p.id_sku = s.id_sku
    JOIN Materiales mat ON p.id_material = mat.id_material
    JOIN Generos_Productos gp ON m.id_genero_producto = gp.id_genero_producto
    LEFT JOIN Tallas_Productos tp ON p.id_producto = tp.id_producto
    LEFT JOIN Productos_Oro_Kilataje pok ON p.id_producto = pok.id_producto
    LEFT JOIN Productos_Plata_Ley ppl ON p.id_producto = ppl.id_producto
    ORDER BY p.id_producto DESC;
END$$

-- =========================================
-- sp_producto_editar_datos
-- Obtiene datos de un producto para edición
-- =========================================
CREATE OR REPLACE PROCEDURE sp_producto_editar_datos(
    IN p_id_producto INT
)
BEGIN
    SELECT 
        p.id_producto,
        p.precio_unitario,
        p.descuento_producto,
        p.costo_unitario,
        p.activo_producto,
        m.nombre_producto,
        c.nombre_categoria,
        s.sku,
        mat.material,
        gp.genero_producto,
        tp.talla,
        pok.kilataje,
        ppl.ley
    FROM Productos p
    JOIN Modelos m ON p.id_modelo = m.id_modelo
    JOIN Categorias c ON m.id_categoria = c.id_categoria
    JOIN Sku s ON p.id_sku = s.id_sku
    JOIN Materiales mat ON p.id_material = mat.id_material
    JOIN Generos_Productos gp ON m.id_genero_producto = gp.id_genero_producto
    LEFT JOIN Tallas_Productos tp ON p.id_producto = tp.id_producto
    LEFT JOIN Productos_Oro_Kilataje pok ON p.id_producto = pok.id_producto
    LEFT JOIN Productos_Plata_Ley ppl ON p.id_producto = ppl.id_producto
    WHERE p.id_producto = p_id_producto;
END$$

-- =========================================
-- sp_producto_imagen_obtener
-- Obtiene la imagen más reciente de un producto
-- =========================================
CREATE OR REPLACE PROCEDURE sp_producto_imagen_obtener(
    IN p_id_producto INT
)
BEGIN
    SELECT ip.url_imagen 
    FROM Imagenes_Productos ip 
    WHERE ip.id_producto = p_id_producto 
    ORDER BY ip.fecha_carga DESC 
    LIMIT 1;
END$$

-- =========================================
-- sp_usuario_rol_admin_obtener
-- Obtiene el id_usuario_rol de un usuario con rol Admin
-- =========================================
CREATE OR REPLACE PROCEDURE sp_usuario_rol_admin_obtener(
    IN p_id_usuario INT
)
BEGIN
    SELECT ur.id_usuario_rol 
    FROM Usuarios_Roles ur
    JOIN Roles r ON ur.id_roles = r.id_roles
    WHERE ur.id_usuario = p_id_usuario 
    AND r.nombre_rol = 'Admin'
    AND ur.activo_usuario_rol = 1
    LIMIT 1;
END$$

-- =========================================
-- sp_usuario_datos_completos_extendido
-- Obtiene datos completos de usuario con municipio y estado
-- =========================================
CREATE OR REPLACE PROCEDURE sp_usuario_datos_completos_extendido(
    IN p_id_usuario INT
)
BEGIN
    SELECT 
        u.nombre_usuario,
        u.nombre_primero,
        u.nombre_segundo,
        u.apellido_paterno,
        u.apellido_materno,
        u.correo,
        u.rfc_usuario,
        u.telefono,
        u.id_direccion,
        d.calle_direccion,
        d.numero_direccion,
        cp.codigo_postal,
        md.municipio_direccion,
        ed.id_estado_direccion,
        ed.estado_direccion
    FROM Usuarios u
    LEFT JOIN Direcciones d ON u.id_direccion = d.id_direccion
    LEFT JOIN Codigos_Postales cp ON d.id_cp = cp.id_cp
    LEFT JOIN Codigos_Postales_Municipios cpm ON cp.id_cp = cpm.id_cp
    LEFT JOIN Municipios_Direcciones md ON cpm.id_municipio_direccion = md.id_municipio_direccion
    LEFT JOIN Codigos_Postales_Estados cpe ON cp.id_cp = cpe.id_cp
    LEFT JOIN Estados_Direcciones ed ON cpe.id_estado_direccion = ed.id_estado_direccion
    WHERE u.id_usuario = p_id_usuario;
END$$

-- =========================================
-- sp_productos_catalogo_inventario
-- Obtiene catálogo de productos para inventario (sin joins complejos)
-- =========================================
CREATE OR REPLACE PROCEDURE sp_productos_catalogo_inventario()
BEGIN
    SELECT 
        p.id_producto,
        p.precio_unitario,
        p.descuento_producto,
        p.costo_unitario,
        p.activo_producto,
        m.nombre_producto,
        m.nombre_producto as nombre,
        s.sku,
        c.nombre_categoria,
        c.id_categoria,
        mat.material,
        gp.genero_producto
    FROM Productos p
    INNER JOIN Modelos m ON p.id_modelo = m.id_modelo
    INNER JOIN Categorias c ON m.id_categoria = c.id_categoria
    INNER JOIN Sku s ON p.id_sku = s.id_sku
    INNER JOIN Materiales mat ON p.id_material = mat.id_material
    INNER JOIN Generos_Productos gp ON m.id_genero_producto = gp.id_genero_producto
    ORDER BY p.id_producto DESC;
END$$

-- =========================================
-- sp_finanzas_pedidos_lista
-- Obtiene lista de pedidos con información de facturas y pagos para finanzas
-- =========================================
CREATE OR REPLACE PROCEDURE sp_finanzas_pedidos_lista()
BEGIN
    SELECT 
        p.id_pedido,
        p.fecha_pedido,
        COALESCE((
            SELECT SUM(pd.cantidad_producto * pr.precio_unitario)
            FROM Pedidos_Detalles pd
            JOIN Productos pr ON pd.id_producto = pr.id_producto
            WHERE pd.id_pedido = p.id_pedido
        ), 0) AS total_pedido,
        ep.estado_pedido,
        CONCAT(
            IFNULL(u.nombre_primero, ''), ' ',
            IFNULL(u.nombre_segundo, ''), ' ',
            IFNULL(u.apellido_paterno, ''), ' ',
            IFNULL(u.apellido_materno, '')
        ) AS nombre_cliente,
        u.nombre_usuario,
        f.id_factura,
        f.folio,
        f.total AS total_factura,
        COALESCE((
            SELECT SUM(mp2.monto_metodo_pago)
            FROM Pagos pa2
            JOIN Montos_Pagos mp2 ON pa2.id_pago = mp2.id_pago
            WHERE pa2.id_factura = f.id_factura
        ), 0) AS total_pagado,
        COALESCE(f.total, 0) - COALESCE((
            SELECT SUM(mp2.monto_metodo_pago)
            FROM Pagos pa2
            JOIN Montos_Pagos mp2 ON pa2.id_pago = mp2.id_pago
            WHERE pa2.id_factura = f.id_factura
        ), 0) AS pendiente,
        CASE
            WHEN f.id_factura IS NULL THEN 'Sin factura'
            WHEN COALESCE((
                SELECT SUM(mp2.monto_metodo_pago)
                FROM Pagos pa2
                JOIN Montos_Pagos mp2 ON pa2.id_pago = mp2.id_pago
                WHERE pa2.id_factura = f.id_factura
            ), 0) >= f.total THEN 'Pagada'
            WHEN COALESCE((
                SELECT SUM(mp2.monto_metodo_pago)
                FROM Pagos pa2
                JOIN Montos_Pagos mp2 ON pa2.id_pago = mp2.id_pago
                WHERE pa2.id_factura = f.id_factura
            ), 0) > 0 THEN 'Parcial'
            ELSE 'Pendiente'
        END AS estado_pago
    FROM Pedidos p
    LEFT JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
    LEFT JOIN Usuarios u ON c.id_usuario = u.id_usuario
    LEFT JOIN Facturas f ON p.id_pedido = f.id_pedido
    ORDER BY p.fecha_pedido DESC
    LIMIT 100;
END$$

-- =========================================
-- sp_finanzas_facturas_pagadas_count
-- Cuenta facturas pagadas completamente
-- =========================================
CREATE OR REPLACE PROCEDURE sp_finanzas_facturas_pagadas_count()
BEGIN
    SELECT COUNT(DISTINCT f.id_factura) as total
    FROM Facturas f
    LEFT JOIN Pagos p ON f.id_factura = p.id_factura
    LEFT JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
    GROUP BY f.id_factura, f.total
    HAVING COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total;
END$$

DELIMITER ;
USE joyeria_db;
DELIMITER $$

DROP PROCEDURE IF EXISTS cliente_perfil_actualizar$$

CREATE PROCEDURE cliente_perfil_actualizar(
    IN var_id_usuario          INT,
    IN var_nombre_usuario      VARCHAR(50),
    IN var_nombre_primero      VARCHAR(50),
    IN var_nombre_segundo      VARCHAR(50),
    IN var_apellido_paterno    VARCHAR(50),
    IN var_apellido_materno    VARCHAR(50),
    IN var_rfc_usuario         VARCHAR(13),
    IN var_telefono            VARCHAR(20),
    IN var_correo              VARCHAR(150),
    IN var_id_genero           INT,
    IN var_codigo_postal       VARCHAR(10),
    IN var_municipio           VARCHAR(100),     -- ignorado
    IN var_id_estado_direccion INT,             -- ignorado
    IN var_calle_direccion     VARCHAR(150),
    IN var_numero_direccion    VARCHAR(20)
)
BEGIN
    DECLARE var_id_cp        INT;
    DECLARE var_id_direccion INT;

    -- =======================================
    -- Normalizar CP: quitar espacios y limitar a 5
    -- =======================================
    SET var_codigo_postal = TRIM(var_codigo_postal);
    SET var_codigo_postal = LEFT(var_codigo_postal, 5);

    -- =======================================
    -- Evitar que numero_direccion sea NULL
    -- =======================================
    SET var_numero_direccion = TRIM(IFNULL(var_numero_direccion, ''));
    IF var_numero_direccion = '' THEN
        SET var_numero_direccion = 'S/N';
    END IF;

    -- =======================================
    -- Actualizar datos del usuario
    -- =======================================
    UPDATE Usuarios
    SET
        nombre_usuario   = var_nombre_usuario,
        nombre_primero   = var_nombre_primero,
        nombre_segundo   = IFNULL(var_nombre_segundo, ''),
        apellido_paterno = var_apellido_paterno,
        apellido_materno = IFNULL(var_apellido_materno, ''),
        rfc_usuario      = IFNULL(var_rfc_usuario, ''),
        telefono         = IFNULL(var_telefono, ''),
        correo           = IFNULL(var_correo, ''),
        id_genero        = var_id_genero
    WHERE id_usuario = var_id_usuario;

    -- =======================================
    -- Código postal (crear si no existe)
    -- =======================================
    SELECT id_cp INTO var_id_cp
    FROM Codigos_Postales
    WHERE codigo_postal = var_codigo_postal
    LIMIT 1;

    IF var_id_cp IS NULL THEN
        INSERT INTO Codigos_Postales(codigo_postal)
        VALUES (var_codigo_postal);
        SET var_id_cp = LAST_INSERT_ID();
    END IF;

    -- =======================================
    -- Dirección del usuario
    -- =======================================
    SELECT id_direccion INTO var_id_direccion
    FROM Usuarios
    WHERE id_usuario = var_id_usuario;

    -- Si no tiene dirección → crear
    IF var_id_direccion IS NULL THEN
        INSERT INTO Direcciones(calle_direccion, numero_direccion, id_cp)
        VALUES (var_calle_direccion, var_numero_direccion, var_id_cp);

        SET var_id_direccion = LAST_INSERT_ID();

        UPDATE Usuarios
        SET id_direccion = var_id_direccion
        WHERE id_usuario = var_id_usuario;

    ELSE
        -- Si ya tiene dirección → actualizarla
        UPDATE Direcciones
        SET
            calle_direccion  = var_calle_direccion,
            numero_direccion = var_numero_direccion,
            id_cp            = var_id_cp
        WHERE id_direccion = var_id_direccion;
    END IF;

    SELECT 'Perfil actualizado exitosamente' AS mensaje;
END$$

DELIMITER ;
DROP PROCEDURE IF EXISTS sp_pedido_estado_obtener;
DELIMITER $$
CREATE PROCEDURE sp_pedido_estado_obtener(
    IN p_id_pedido INT
)
BEGIN
    SELECT ep.estado_pedido
    FROM Pedidos p
    JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    WHERE p.id_pedido = p_id_pedido;
END$$
DELIMITER ;
DELIMITER $$
CREATE OR REPLACE PROCEDURE sp_factura_verificar_existente(
    IN p_id_pedido INT
)
BEGIN
    SELECT id_factura 
    FROM Facturas 
    WHERE id_pedido = p_id_pedido;
END$$

CREATE OR REPLACE PROCEDURE sp_pedido_verificar_detalles(
    IN p_id_pedido INT
)
BEGIN
    SELECT COUNT(*) as total_detalles
    FROM Pedidos_Detalles
    WHERE id_pedido = p_id_pedido;
END$$

-- =========================================
-- sp_empresa_obtener_por_nombre
-- Obtiene una empresa por su nombre
-- =========================================
CREATE OR REPLACE PROCEDURE sp_empresa_obtener_por_nombre(
    IN p_nombre_empresa VARCHAR(255)
)
BEGIN
    SELECT id_empresa
    FROM Empresas
    WHERE nombre_empresa = p_nombre_empresa
    LIMIT 1;
END$$

-- =========================================
-- sp_pedido_subtotal_calcular
-- Calcula el subtotal de un pedido
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedido_subtotal_calcular(
    IN p_id_pedido INT
)
BEGIN
    SELECT COALESCE(SUM(pr.precio_unitario * pd.cantidad_producto), 0) as subtotal
    FROM Pedidos_Detalles pd
    JOIN Productos pr ON pr.id_producto = pd.id_producto
    WHERE pd.id_pedido = p_id_pedido;
END$$

-- =========================================
-- sp_factura_obtener_por_pedido
-- Obtiene la factura de un pedido
-- =========================================
CREATE OR REPLACE PROCEDURE sp_factura_obtener_por_pedido(
    IN p_id_pedido INT
)
BEGIN
    SELECT id_factura, folio, total
    FROM Facturas
    WHERE id_pedido = p_id_pedido
    ORDER BY id_factura DESC
    LIMIT 1;
END$$

-- =========================================
-- sp_pedido_verificar_cliente
-- Verifica que un pedido pertenezca a un cliente
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedido_verificar_cliente(
    IN p_id_pedido INT,
    IN p_id_usuario INT
)
BEGIN
    SELECT 1
    FROM Pedidos p
    JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    JOIN Clientes c ON pc.id_cliente = c.id_cliente
    WHERE p.id_pedido = p_id_pedido AND c.id_usuario = p_id_usuario;
END$$

-- =========================================
-- sp_factura_verificar_cliente
-- Verifica que una factura pertenezca a un cliente
-- =========================================
CREATE OR REPLACE PROCEDURE sp_factura_verificar_cliente(
    IN p_id_factura INT,
    IN p_id_usuario INT
)
BEGIN
    SELECT p.id_pedido, ep.estado_pedido
    FROM Pedidos p
    LEFT JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
    LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
    JOIN Facturas f ON p.id_pedido = f.id_pedido
    WHERE f.id_factura = p_id_factura AND c.id_usuario = p_id_usuario;
END$$

-- =========================================
-- sp_factura_info_cliente
-- Obtiene información de factura con verificación de cliente
-- =========================================
CREATE OR REPLACE PROCEDURE sp_factura_info_cliente(
    IN p_id_factura INT,
    IN p_id_usuario INT
)
BEGIN
    SELECT f.id_factura, f.total, COALESCE(SUM(mp.monto_metodo_pago), 0) as total_pagado
    FROM Facturas f
    JOIN Pedidos p ON f.id_pedido = p.id_pedido
    JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
    JOIN Clientes c ON pc.id_cliente = c.id_cliente
    LEFT JOIN Pagos pa ON f.id_factura = pa.id_factura
    LEFT JOIN Montos_Pagos mp ON pa.id_pago = mp.id_pago
    WHERE f.id_factura = p_id_factura AND c.id_usuario = p_id_usuario
    GROUP BY f.id_factura, f.total;
END$$

-- =========================================
-- sp_factura_info_pagos
-- Obtiene información de factura con pagos
-- =========================================
CREATE OR REPLACE PROCEDURE sp_factura_info_pagos(
    IN p_id_factura INT
)
BEGIN
    SELECT
        f.id_factura,
        f.folio,
        f.total AS total_factura,
        COALESCE(SUM(mp.monto_metodo_pago), 0) AS total_pagado,
        (f.total - COALESCE(SUM(mp.monto_metodo_pago), 0)) AS pendiente,
        CASE
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total THEN 'Pagada'
            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) > 0 THEN 'Parcial'
            ELSE 'Pendiente'
        END AS estado_pago
    FROM Facturas f
    LEFT JOIN Pagos p ON f.id_factura = p.id_factura
    LEFT JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
    WHERE f.id_factura = p_id_factura
    GROUP BY f.id_factura, f.folio, f.total;
END$$

-- =========================================
-- sp_factura_pagos_lista
-- Obtiene lista de pagos de una factura
-- =========================================
CREATE OR REPLACE PROCEDURE sp_factura_pagos_lista(
    IN p_id_factura INT
)
BEGIN
    SELECT
        p.id_pago,
        p.fecha_pago,
        mp.monto_metodo_pago,
        m.nombre_metodo_pago
    FROM Pagos p
    JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
    JOIN Metodos_Pagos m ON mp.id_metodo_pago = m.id_metodo_pago
    WHERE p.id_factura = p_id_factura
    ORDER BY p.fecha_pago DESC;
END$$

-- =========================================
-- sp_usuario_datos_completos
-- Obtiene datos completos de un usuario
-- =========================================
CREATE OR REPLACE PROCEDURE sp_usuario_datos_completos(
    IN p_id_usuario INT
)
BEGIN
    SELECT
        u.nombre_usuario,
        u.nombre_primero,
        u.nombre_segundo,
        u.apellido_paterno,
        u.apellido_materno,
        u.correo,
        u.id_genero,
        u.rfc_usuario,
        u.telefono,
        u.id_direccion,
        d.calle_direccion,
        d.numero_direccion,
        cp.codigo_postal
    FROM Usuarios u
    LEFT JOIN Direcciones d ON u.id_direccion = d.id_direccion
    LEFT JOIN Codigos_Postales cp ON d.id_cp = cp.id_cp
    WHERE u.id_usuario = p_id_usuario;
END$$

-- =========================================
-- sp_usuario_rol_activo_obtener
-- Obtiene el primer rol activo de un usuario
-- =========================================
CREATE OR REPLACE PROCEDURE sp_usuario_rol_activo_obtener(
    IN p_id_usuario INT
)
BEGIN
    SELECT id_usuario_rol
    FROM Usuarios_Roles
    WHERE id_usuario = p_id_usuario
    AND activo_usuario_rol = 1
    LIMIT 1;
END$$

-- =========================================
-- sp_pedido_detalles_obtener
-- Obtiene los detalles de un pedido
-- =========================================
CREATE OR REPLACE PROCEDURE sp_pedido_detalles_obtener(
    IN p_id_pedido INT
)
BEGIN
    SELECT
        pd.id_pedido_detalle,
        pd.id_producto,
        pd.cantidad_producto,
        m.nombre_producto,
        p.precio_unitario,
        s.sku
    FROM Pedidos_Detalles pd
    JOIN Productos p ON pd.id_producto = p.id_producto
    JOIN Modelos m ON p.id_modelo = m.id_modelo
    JOIN Sku s ON p.id_sku = s.id_sku
    WHERE pd.id_pedido = p_id_pedido;
END$$

-- =========================================
-- sp_producto_por_sku
-- Obtiene un producto por su SKU
-- =========================================
CREATE OR REPLACE PROCEDURE sp_producto_por_sku(
    IN p_sku VARCHAR(50)
)
BEGIN
    SELECT p.id_producto
    FROM Productos p
    JOIN Sku s ON p.id_sku = s.id_sku
    WHERE s.sku = p_sku
    LIMIT 1;
END$$

-- =========================================
-- sp_producto_sucursal_obtener
-- Obtiene la sucursal de un producto
-- =========================================
CREATE OR REPLACE PROCEDURE sp_producto_sucursal_obtener(
    IN p_id_producto INT
)
BEGIN
    SELECT s.nombre_sucursal, s.id_sucursal
    FROM Sucursales_Productos sp
    JOIN Sucursales s ON sp.id_sucursal = s.id_sucursal
    WHERE sp.id_producto = p_id_producto
    AND s.activo_sucursal = 1
    LIMIT 1;
END$$

-- =========================================
-- sp_sucursal_gestor_obtener
-- Obtiene la sucursal de un gestor de sucursal
-- =========================================
CREATE OR REPLACE PROCEDURE sp_sucursal_gestor_obtener(
    IN p_id_usuario INT
)
BEGIN
    SELECT s.id_sucursal, s.nombre_sucursal
    FROM Usuarios_Roles ur
    JOIN Roles r ON ur.id_roles = r.id_roles
    JOIN Usuarios_Roles_Sucursales urs ON ur.id_usuario_rol_sucursal = urs.id_usuario_rol_sucursal
    JOIN Roles_Sucursales rs ON urs.id_roles_sucursal = rs.id_roles_sucursal
    JOIN Sucursales s ON rs.id_sucursal = s.id_sucursal
    WHERE ur.id_usuario = p_id_usuario
    AND ur.activo_usuario_rol = 1
    AND urs.activo_usuario_rol_sucursal = 1
    AND s.activo_sucursal = 1
    AND r.nombre_rol = 'Gestor de Sucursal'
    LIMIT 1;
END$$

-- =========================================
-- sp_auditor_kpis_basicos
-- Obtiene KPIs básicos para auditoría
-- =========================================
CREATE OR REPLACE PROCEDURE sp_auditor_kpis_basicos()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM Pedidos) as total_pedidos,
        (SELECT COUNT(*) FROM Facturas) as total_facturas,
        (SELECT COUNT(*) FROM Devoluciones) as total_devoluciones;
END$$

-- =========================================
-- sp_auditor_discrepancias
-- Obtiene discrepancias para auditoría
-- =========================================
CREATE OR REPLACE PROCEDURE sp_auditor_discrepancias()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM Pedidos WHERE estado_pedido = 'Cancelado') as pedidos_cancelados,
        (SELECT COUNT(*) FROM Devoluciones_Detalles dd
         JOIN Estados_Devoluciones ed ON dd.id_estado_devolucion = ed.id_estado_devolucion
         WHERE ed.estado_devolucion = 'Rechazado') as devoluciones_rechazadas;
END$$
        -- Script para corregir el tipo de dato de kilatajeSP en productoAlta y productoActualizar
-- Ejecutar: mysql -u joyeria_user -p joyeria_db < scripts/fix_producto_kilataje.sql

DELIMITER $$

-- =========================================
-- productoActualizar
-- =========================================
CREATE OR REPLACE PROCEDURE productoActualizar(
    IN skuSP                VARCHAR(20),
    IN nombre_categoriaSP   VARCHAR(100),
    IN materialSP           VARCHAR(100),
    IN genero_productoSP    VARCHAR(50),
    IN nombre_productoSP    VARCHAR(150),
    IN precio_unitarioSP    DECIMAL(10,2),
    IN descuento_productoSP DECIMAL(5,2),
    IN costo_unitarioSP     DECIMAL(10,2),
    IN activo_productoSP    TINYINT,
    IN tallaSP              VARCHAR(20),
    IN kilatajeSP           VARCHAR(10),
    IN leySP                DECIMAL(10,2)
)
BEGIN
    DECLARE IDsku INT;
    DECLARE IDproducto INT;
    DECLARE IDmodelo INT;
    DECLARE IDcategoria INT;
    DECLARE IDmaterial INT;
    DECLARE IDgenero INT;
    DECLARE filaOro INT;
    DECLARE filaPlata INT;

    -- Buscar SKU
    SELECT id_sku
    INTO IDsku
    FROM Sku
    WHERE sku = UPPER(TRIM(skuSP));

    IF IDsku IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El SKU no existe, no se puede actualizar';
    END IF;

    -- Producto / modelo / material actual
    SELECT id_producto, id_modelo, id_material
    INTO IDproducto, IDmodelo, IDmaterial
    FROM Productos
    WHERE id_sku = IDsku;

    -- Categoría
    IF nombre_categoriaSP IS NOT NULL THEN
        SET nombre_categoriaSP = CONCAT(
            UPPER(SUBSTR(TRIM(nombre_categoriaSP),1,1)),
            LOWER(SUBSTR(TRIM(nombre_categoriaSP),2))
        );

        SELECT id_categoria
        INTO IDcategoria
        FROM Categorias
        WHERE nombre_categoria = nombre_categoriaSP;

        IF IDcategoria IS NULL THEN
            INSERT INTO Categorias(nombre_categoria, activo_categoria)
            VALUES (nombre_categoriaSP, TRUE);

            SELECT id_categoria
            INTO IDcategoria
            FROM Categorias
            WHERE nombre_categoria = nombre_categoriaSP;
        END IF;
    END IF;

    -- Material
    IF materialSP IS NOT NULL THEN
        SET materialSP = TRIM(materialSP);
        SET materialSP = CONCAT(
            UPPER(SUBSTR(materialSP,1,1)),
            LOWER(SUBSTR(materialSP,2))
        );

        SELECT id_material
        INTO IDmaterial
        FROM Materiales
        WHERE material = materialSP;

        IF IDmaterial IS NULL THEN
            INSERT INTO Materiales (material)
            VALUES (materialSP);

            SELECT id_material
            INTO IDmaterial
            FROM Materiales
            WHERE material = materialSP;
        END IF;
    END IF;

    -- Género
    IF genero_productoSP IS NOT NULL THEN
        SET genero_productoSP = TRIM(genero_productoSP);
        SET genero_productoSP = CONCAT(
            UPPER(SUBSTR(genero_productoSP,1,1)),
            LOWER(SUBSTR(genero_productoSP,2))
        );

        SELECT id_genero_producto
        INTO IDgenero
        FROM Generos_Productos
        WHERE genero_producto = genero_productoSP;

        IF IDgenero IS NULL THEN
            INSERT INTO Generos_Productos(genero_producto)
            VALUES (genero_productoSP);

            SELECT id_genero_producto
            INTO IDgenero
            FROM Generos_Productos
            WHERE genero_producto = genero_productoSP;
        END IF;
    END IF;

    -- Modelo
    IF nombre_productoSP IS NOT NULL AND IDcategoria IS NOT NULL AND IDgenero IS NOT NULL THEN
        SELECT id_modelo
        INTO IDmodelo
        FROM Modelos
        WHERE nombre_producto = nombre_productoSP
          AND id_categoria = IDcategoria
          AND id_genero_producto = IDgenero;

        IF IDmodelo IS NULL THEN
            INSERT INTO Modelos(nombre_producto, id_categoria, id_genero_producto)
            VALUES (nombre_productoSP, IDcategoria, IDgenero);

            SELECT id_modelo
            INTO IDmodelo
            FROM Modelos
            WHERE nombre_producto = nombre_productoSP
              AND id_categoria = IDcategoria
              AND id_genero_producto = IDgenero;
        END IF;

        UPDATE Productos
        SET id_modelo = IDmodelo
        WHERE id_producto = IDproducto;
    END IF;

    IF IDmaterial IS NOT NULL THEN
        UPDATE Productos
        SET id_material = IDmaterial
        WHERE id_producto = IDproducto;
    END IF;

    IF precio_unitarioSP IS NOT NULL THEN
        UPDATE Productos
        SET precio_unitario = precio_unitarioSP
        WHERE id_producto = IDproducto;
    END IF;

    IF descuento_productoSP IS NOT NULL THEN
        UPDATE Productos
        SET descuento_producto = descuento_productoSP
        WHERE id_producto = IDproducto;
    END IF;

    IF costo_unitarioSP IS NOT NULL THEN
        UPDATE Productos
        SET costo_unitario = costo_unitarioSP
        WHERE id_producto = IDproducto;
    END IF;

    IF activo_productoSP IS NOT NULL THEN
        UPDATE Productos
        SET activo_producto = activo_productoSP
        WHERE id_producto = IDproducto;
    END IF;

    -- Tallas (solo Anillos)
    IF nombre_categoriaSP = 'Anillos' AND tallaSP IS NOT NULL THEN
        SET tallaSP = TRIM(tallaSP);

        INSERT INTO Tallas_Productos (id_producto, talla)
        VALUES (IDproducto, tallaSP)
        ON DUPLICATE KEY UPDATE talla = tallaSP;
    END IF;

    -- Oro / kilataje
    IF kilatajeSP IS NOT NULL THEN
        IF materialSP <> 'Oro' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No se puede asignar kilataje a un producto que no es Oro';
        ELSE
            UPDATE Productos_Oro_Kilataje
            SET kilataje = kilatajeSP
            WHERE id_producto = IDproducto;
        END IF;
    END IF;

    IF materialSP = 'Oro' THEN
        DELETE FROM Productos_Plata_Ley
        WHERE id_producto = IDproducto;

        SELECT COUNT(*)
        INTO filaOro
        FROM Productos_Oro_Kilataje
        WHERE id_producto = IDproducto;

        IF filaOro = 0 THEN
            INSERT INTO Productos_Oro_Kilataje (id_producto)
            VALUES (IDproducto);
        END IF;
    END IF;

    -- Plata / ley
    IF leySP IS NOT NULL THEN
        IF materialSP <> 'Plata' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No se puede asignar ley a un producto que no es Plata';
        ELSE
            UPDATE Productos_Plata_Ley
            SET ley = leySP
            WHERE id_producto = IDproducto;
        END IF;
    END IF;

    IF materialSP = 'Plata' THEN
        DELETE FROM Productos_Oro_Kilataje
        WHERE id_producto = IDproducto;

        SELECT COUNT(*)
        INTO filaPlata
        FROM Productos_Plata_Ley
        WHERE id_producto = IDproducto;

        IF filaPlata = 0 THEN
            INSERT INTO Productos_Plata_Ley (id_producto)
            VALUES (IDproducto);
        END IF;
    END IF;
END$$

DELIMITER ;

-- =========================================
-- productoAlta
-- =========================================
CREATE OR REPLACE PROCEDURE productoAlta(
    IN nombre_categoriaSP   VARCHAR(100),
    IN materialSP           VARCHAR(100),
    IN skuSP                VARCHAR(20),
    IN genero_productoSP    VARCHAR(50),
    IN nombre_productoSP    VARCHAR(150),
    IN precio_unitarioSP    DECIMAL(10,2),
    IN descuento_productoSP DECIMAL(5,2),
    IN costo_unitarioSP     DECIMAL(10,2),
    IN tallaSP              VARCHAR(20),
    IN kilatajeSP           VARCHAR(10),
    IN leySP                DECIMAL(10,2)
)
BEGIN
    DECLARE existeIDCategoria INT;
    DECLARE existeIDMaterial INT;
    DECLARE existeSKU INT;
    DECLARE IDsku INT;
    DECLARE existeIDGeneroProducto INT;
    DECLARE talla INT;
    DECLARE existeIDModelo INT DEFAULT NULL;
    DECLARE IDmodelo INT DEFAULT NULL;
    DECLARE IDproducto INT;
    DECLARE v_mensaje_error VARCHAR(500);

    -- Normalizar categorÃ­a
    SET nombre_categoriaSP = TRIM(nombre_categoriaSP);
    SET nombre_categoriaSP = CONCAT(
        UPPER(SUBSTR(nombre_categoriaSP,1,1)),
        LOWER(SUBSTR(nombre_categoriaSP,2))
    );

    SELECT id_categoria
    INTO existeIDCategoria
    FROM Categorias
    WHERE nombre_categoria = nombre_categoriaSP;

    IF existeIDCategoria IS NULL THEN
        INSERT INTO Categorias(nombre_categoria, activo_categoria)
        VALUES (nombre_categoriaSP, TRUE);

        SELECT id_categoria
        INTO existeIDCategoria
        FROM Categorias
        WHERE nombre_categoria = nombre_categoriaSP;
    END IF;

    IF nombre_categoriaSP = 'Anillos' AND tallaSP IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Debe especificar la talla para anillos';
    END IF;

    -- Material
    SET materialSP = TRIM(materialSP);
    SET materialSP = CONCAT(
        UPPER(SUBSTR(materialSP,1,1)),
        LOWER(SUBSTR(materialSP,2))
    );

    SELECT id_material
    INTO existeIDMaterial
    FROM Materiales
    WHERE material = materialSP;

    IF existeIDMaterial IS NULL THEN
        INSERT INTO Materiales (material)
        VALUES (materialSP);

        SELECT id_material
        INTO existeIDMaterial
        FROM Materiales
        WHERE material = materialSP;
    END IF;

    IF materialSP = 'Oro' AND kilatajeSP IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Debe especificar el kilataje para productos de oro';
    END IF;

    IF materialSP = 'Plata' AND leySP IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Debe especificar la ley para productos de plata';
    END IF;

    -- SKU normalizado
    SET skuSP = UPPER(TRIM(skuSP));
    SET skuSP = REPLACE(skuSP,'AUR', 'AUR-');

    WHILE LOCATE(' ', skuSP) > 0 DO
        SET skuSP = REPLACE(skuSP, ' ', '');
    END WHILE;

    IF skuSP NOT LIKE 'AUR-%' THEN
        SET skuSP = CONCAT('AUR-', skuSP);
    END IF;

    -- Validar formato del SKU después de normalización
    IF skuSP NOT REGEXP '^AUR-[0-9]{3}[A-Za-z]$' THEN
        SET v_mensaje_error = CONCAT('Formato de SKU inválido. El formato debe ser: AUR-999X (8 caracteres). SKU recibido: "', skuSP, '" (', LENGTH(skuSP), ' caracteres). Ejemplos válidos: AUR-001A, AUR-123B, AUR-999Z');
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_mensaje_error;
    END IF;

    IF LENGTH(skuSP) <> 8 THEN
        SET v_mensaje_error = CONCAT('El SKU debe tener exactamente 8 caracteres. SKU recibido: "', skuSP, '" tiene ', LENGTH(skuSP), ' caracteres. Formato requerido: AUR-999X');
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_mensaje_error;
    END IF;

    SELECT COUNT(*)
    INTO existeSKU
    FROM Sku
    WHERE sku = skuSP;

    IF existeSKU > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ya se registro ese producto.';
    ELSE
        INSERT INTO Sku(sku)
        VALUES (skuSP);

        SELECT id_sku
        INTO IDsku
        FROM Sku
        WHERE sku = skuSP;
    END IF;

    -- GÃ©nero
    SET genero_productoSP = TRIM(genero_productoSP);
    SET genero_productoSP = CONCAT(
        UPPER(SUBSTR(genero_productoSP,1,1)),
        LOWER(SUBSTR(genero_productoSP,2))
    );

    SELECT id_genero_producto
    INTO existeIDGeneroProducto
    FROM Generos_Productos
    WHERE genero_producto = genero_productoSP;

    IF existeIDGeneroProducto IS NULL THEN
        INSERT INTO Generos_Productos(genero_producto)
        VALUES (genero_productoSP);

        SELECT id_genero_producto
        INTO existeIDGeneroProducto
        FROM Generos_Productos
        WHERE genero_producto = genero_productoSP;
    END IF;

    -- Modelo
    SELECT id_modelo
    INTO existeIDModelo
    FROM Modelos
    WHERE nombre_producto = nombre_productoSP
      AND id_categoria = existeIDCategoria
      AND id_genero_producto = existeIDGeneroProducto;

    IF existeIDModelo IS NULL THEN
        INSERT INTO Modelos(nombre_producto, id_categoria, id_genero_producto)
        VALUES (nombre_productoSP, existeIDCategoria, existeIDGeneroProducto);

        SELECT id_modelo
        INTO existeIDModelo
        FROM Modelos
        WHERE nombre_producto = nombre_productoSP;
    END IF;

    SET IDmodelo = existeIDModelo;

    -- Producto
    INSERT INTO Productos (
        id_sku,
        id_modelo,
        id_material,
        precio_unitario,
        descuento_producto,
        costo_unitario,
        activo_producto
    ) VALUES (
        IDsku,
        IDmodelo,
        existeIDMaterial,
        precio_unitarioSP,
        descuento_productoSP,
        costo_unitarioSP,
        TRUE
    );

    SELECT id_producto
    INTO IDproducto
    FROM Productos
    WHERE id_sku = IDsku;

    -- Talla (solo anillos)
    IF nombre_categoriaSP = 'Anillos' THEN
        INSERT INTO Tallas_Productos(talla, id_producto)
        VALUES (tallaSP, IDproducto);
    END IF;

    -- Oro
    IF materialSP = 'Oro' THEN
        INSERT INTO Productos_Oro_Kilataje(id_producto, kilataje)
        VALUES (IDproducto, kilatajeSP);
    END IF;

    -- Plata
    IF materialSP = 'Plata' THEN
        INSERT INTO Productos_Plata_Ley(id_producto, ley)
        VALUES (IDproducto, leySP);
    END IF;
END$$

