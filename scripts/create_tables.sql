-- Como 'user-joyeria':
CREATE TABLE IF NOT EXISTS Estados_Direcciones (
    id_estado_direccion INT AUTO_INCREMENT PRIMARY KEY,
    estado_direccion ENUM( 
        'Aguascalientes',
        'Baja California',
        'Baja California Sur',
        'Campeche',
        'Coahuila',
        'Colima',
        'Chiapas',
        'Chihuahua',
        'Ciudad de México',
        'Durango',
        'Guanajuato',
        'Guerrero',
        'Hidalgo',
        'Jalisco',
        'México',
        'Michoacán',
        'Morelos',
        'Nayarit', 
        'Nuevo León',
        'Oaxaca',
        'Puebla',
        'Querétaro',
        'Quintana Roo',
        'San Luis Potosí',
        'Sinaloa',
        'Sonora',
        'Tabasco',
        'Tamaulipas',
        'Tlaxcala',
        'Veracruz',
        'Yucatán',
        'Zacatecas'  ) NOT NULL 
);



CREATE TABLE IF NOT EXISTS Municipios_Direcciones (
    id_municipio_direccion INT AUTO_INCREMENT PRIMARY KEY,
    municipio_direccion VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS Codigos_Postales (
    id_cp INT AUTO_INCREMENT PRIMARY KEY,
    codigo_postal CHAR(5) NOT NULL UNIQUE
);


CREATE TABLE IF NOT EXISTS Codigos_Postales_Estados (
    id_cp_estado INT AUTO_INCREMENT PRIMARY KEY,
    id_cp INT NOT NULL,
    id_estado_direccion INT NOT NULL,
    FOREIGN KEY (id_cp) REFERENCES Codigos_Postales(id_cp),
    FOREIGN KEY (id_estado_direccion) REFERENCES Estados_Direcciones(id_estado_direccion),
    UNIQUE (id_cp, id_estado_direccion)
);
CREATE TABLE IF NOT EXISTS Codigos_Postales_Municipios (
    id_cp_municipio_direccion INT AUTO_INCREMENT PRIMARY KEY,
    id_cp INT NOT NULL,
    id_municipio_direccion INT NOT NULL,
    FOREIGN KEY (id_cp) REFERENCES Codigos_Postales(id_cp),    
    FOREIGN KEY (id_municipio_direccion) REFERENCES Municipios_Direcciones(id_municipio_direccion),
    UNIQUE (id_cp, id_municipio_direccion)
);

CREATE TABLE IF NOT EXISTS Direcciones (
    id_direccion INT AUTO_INCREMENT PRIMARY KEY,
    calle_direccion VARCHAR(200) NOT NULL,
    numero_direccion VARCHAR(10) NOT NULL,
    id_cp INT NOT NULL,
    FOREIGN KEY (id_cp) REFERENCES Codigos_Postales(id_cp)
);



CREATE TABLE IF NOT EXISTS Empresas(
    id_empresa INT AUTO_INCREMENT primary key,    
    nombre_empresa VARCHAR(200) NOT NULL,
    rfc_empresa CHAR(12) NOT NULL UNIQUE,
    id_direccion INT NOT NULL,
    correo_empresa VARCHAR(100) NOT NULL,
    FOREIGN KEY (id_direccion) REFERENCES Direcciones(id_direccion)
);


CREATE TABLE IF NOT EXISTS Generos(
    id_genero INT AUTO_INCREMENT PRIMARY KEY,    
    genero VARCHAR(200) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS Usuarios(
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    nombre_usuario VARCHAR(50) NOT NULL UNIQUE,
    nombre_primero VARCHAR(50) NOT NULL,
    nombre_segundo VARCHAR(50) NULL,
    apellido_paterno VARCHAR(50) NOT NULL,
    apellido_materno VARCHAR(50) NULL,
    rfc_usuario CHAR(13) NULL UNIQUE,
    telefono VARCHAR(15) NULL, 
    correo VARCHAR(150) NULL, 
    id_genero INT NULL,  
    id_direccion INT NULL,  
    contrasena VARCHAR(500) NOT NULL,
    fecha_registro_usuario DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_genero) REFERENCES Generos(id_genero),
    FOREIGN KEY (id_direccion) REFERENCES Direcciones(id_direccion)
);

CREATE TABLE IF NOT EXISTS Roles(
    id_roles INT PRIMARY KEY AUTO_INCREMENT,
    nombre_rol VARCHAR(50) NOT NULL UNIQUE,
    descripcion_roles VARCHAR(255) NULL
);


CREATE TABLE IF NOT EXISTS Sucursales (
    id_sucursal INT PRIMARY KEY AUTO_INCREMENT,
    nombre_sucursal VARCHAR(100) NOT NULL UNIQUE,
    id_direccion INT NOT NULL,
    activo_sucursal BOOLEAN NOT NULL,
    FOREIGN KEY (id_direccion) REFERENCES Direcciones(id_direccion)
);


CREATE TABLE IF NOT EXISTS Roles_Sucursales (
    id_roles_sucursal INT PRIMARY KEY AUTO_INCREMENT,
    id_roles INT NOT NULL,
    id_sucursal INT NOT NULL,
    FOREIGN KEY (id_roles) REFERENCES Roles(id_roles),
    FOREIGN KEY (id_sucursal) REFERENCES Sucursales(id_sucursal),
    UNIQUE (id_roles, id_sucursal)
);

CREATE TABLE IF NOT EXISTS Usuarios_Roles_Sucursales (
    id_usuario_rol_sucursal INT PRIMARY KEY AUTO_INCREMENT,
    id_usuario INT NOT NULL,
    id_roles_sucursal INT NOT NULL,
    activo_usuario_rol_sucursal BOOLEAN NOT NULL,
    FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario),
    FOREIGN KEY (id_roles_sucursal) REFERENCES
    Roles_Sucursales(id_roles_sucursal),
    UNIQUE (id_usuario, id_roles_sucursal)
);

CREATE TABLE IF NOT EXISTS Usuarios_Roles(
    id_usuario_rol INT PRIMARY KEY AUTO_INCREMENT,
    id_usuario INT NOT NULL,
    id_roles INT NOT NULL,
    id_usuario_rol_sucursal INT NULL,
    fecha_asignacion DATE NOT NULL DEFAULT CURRENT_DATE,
    activo_usuario_rol BOOLEAN NOT NULL,
    FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario),
    FOREIGN KEY (id_roles) REFERENCES Roles(id_roles),
    FOREIGN KEY (id_usuario_rol_sucursal) REFERENCES Usuarios_Roles_Sucursales(id_usuario_rol_sucursal)

);

CREATE TABLE IF NOT EXISTS Clasificaciones (
    id_clasificacion INT PRIMARY KEY AUTO_INCREMENT,
    nombre_clasificacion VARCHAR(50) NOT NULL UNIQUE,
    descuento_clasificacion TINYINT NOT NULL,  
    compra_min DECIMAL(10,2) NULL,
    compra_max DECIMAL(10,2) NULL,
    descripcion_clasificacion VARCHAR(255) NULL,
    ultima_actualizacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);


CREATE TABLE IF NOT EXISTS Clientes (
    id_cliente INT PRIMARY KEY AUTO_INCREMENT,
    id_clasificacion INT NULL,
    id_usuario INT NOT NULL,
    FOREIGN KEY (id_clasificacion) REFERENCES Clasificaciones(id_clasificacion),
    FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario)
);

CREATE TABLE IF NOT EXISTS Categorias (
    id_categoria INT PRIMARY KEY AUTO_INCREMENT,
    nombre_categoria VARCHAR(50) NOT NULL UNIQUE,
    activo_categoria BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS Generos_Productos (
    id_genero_producto INT PRIMARY KEY AUTO_INCREMENT,
    genero_producto VARCHAR(20) NOT NULL UNIQUE
);


CREATE TABLE IF NOT EXISTS Modelos (
    id_modelo INT PRIMARY KEY AUTO_INCREMENT,
    nombre_producto VARCHAR(150) NOT NULL UNIQUE,
    id_categoria INT NOT NULL,
    id_genero_producto INT NOT NULL,
    FOREIGN KEY (id_categoria) REFERENCES Categorias(id_categoria),
    FOREIGN KEY (id_genero_producto) REFERENCES Generos_Productos(id_genero_producto)
);




CREATE TABLE IF NOT EXISTS Sku (
    id_sku INT PRIMARY KEY AUTO_INCREMENT,
    sku VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS Materiales (
    id_material INT PRIMARY KEY AUTO_INCREMENT,
    material VARCHAR(30) NOT NULL UNIQUE
);


CREATE TABLE IF NOT EXISTS Productos (
    id_producto INT PRIMARY KEY AUTO_INCREMENT,
    id_sku INT NOT NULL UNIQUE,
    id_modelo INT NOT NULL,
    id_material INT NOT NULL, 
    precio_unitario DECIMAL(10,2) NOT NULL,
    descuento_producto TINYINT NULL,
    costo_unitario DECIMAL(10,2) NOT NULL,
    fecha_actualizacion_producto  TIMESTAMP NOT NULL  DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    activo_producto BOOLEAN NOT NULL,
    FOREIGN KEY (id_sku ) REFERENCES Sku(id_sku ),
    FOREIGN KEY (id_modelo) REFERENCES Modelos(id_modelo),
    FOREIGN KEY (id_material) REFERENCES Materiales(id_material)
);

CREATE TABLE IF NOT EXISTS Tallas_Productos (
    id_talla_producto INT PRIMARY KEY AUTO_INCREMENT,
    talla ENUM('4','4,5','5','5,5','6','6,5','7','7,5','8','8,5','9','9,5','10','10,5','11','11,5','12') NOT NULL,
    id_producto INT NOT NULL, 
    FOREIGN KEY (id_producto ) REFERENCES Productos (id_producto),
    UNIQUE (id_producto, talla) 
);

CREATE TABLE IF NOT EXISTS Productos_Oro_Kilataje (
    id_producto_oro_kilataje INT PRIMARY KEY AUTO_INCREMENT,
    id_producto INT NOT NULL UNIQUE,
    kilataje ENUM('10K', '14K', '18K', '24K') NOT NULL,
    FOREIGN KEY (id_producto) REFERENCES Productos(id_producto)
);

CREATE TABLE IF NOT EXISTS Productos_Plata_Ley (
    id_producto_plata_ley INT PRIMARY KEY AUTO_INCREMENT,
    id_producto INT NOT NULL UNIQUE,
    ley ENUM('800','830','835','900','925','950','999') NOT NULL,
    FOREIGN KEY (id_producto) REFERENCES Productos(id_producto)
);


CREATE TABLE IF NOT EXISTS Sucursales_Productos (
    id_sucursal_producto INT PRIMARY KEY AUTO_INCREMENT,
    id_sucursal INT NOT NULL,
    id_producto INT NOT NULL,
    stock_ideal INT NOT NULL,
    stock_actual INT NOT NULL,
    stock_maximo INT NOT NULL,
    FOREIGN KEY (id_sucursal) REFERENCES Sucursales(id_sucursal),
    FOREIGN KEY (id_producto) REFERENCES Productos(id_producto),
    UNIQUE (id_sucursal, id_producto)
);

CREATE TABLE IF NOT EXISTS Tipos_Cambios (
    id_tipo_cambio INT PRIMARY KEY AUTO_INCREMENT,
    tipo_cambio ENUM('Entrada','Salida','Ajuste') NOT NULL,
    descripcion VARCHAR(255) NULL
);

CREATE TABLE IF NOT EXISTS Cambios_Sucursal (
    id_cambio INT PRIMARY KEY AUTO_INCREMENT,
    id_usuario_rol INT NOT NULL,
    id_tipo_cambio INT NOT NULL,
    motivo_cambio VARCHAR(200) NULL,
    fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_usuario_rol) REFERENCES Usuarios_Roles(id_usuario_rol),
    FOREIGN KEY (id_tipo_cambio) REFERENCES Tipos_Cambios(id_tipo_cambio)
);

CREATE TABLE IF NOT EXISTS Tipo_Entradas (
    id_entrada INT PRIMARY KEY AUTO_INCREMENT,
    id_cambio INT NOT NULL,
    id_sucursal_producto_destino INT NOT NULL,
    cantidad_entrada INT NOT NULL ,
    FOREIGN KEY (id_cambio) REFERENCES Cambios_Sucursal (id_cambio),
    FOREIGN KEY (id_sucursal_producto_destino) REFERENCES Sucursales_Productos (id_sucursal_producto)
);

CREATE TABLE IF NOT EXISTS Tipo_Salidas (
    id_salida INT PRIMARY KEY AUTO_INCREMENT,
    id_cambio INT NOT NULL,
    id_sucursal_producto_origen INT NOT NULL,
    cantidad_salida INT NOT NULL ,
    FOREIGN KEY (id_cambio) REFERENCES Cambios_Sucursal (id_cambio),
    FOREIGN KEY (id_sucursal_producto_origen) REFERENCES Sucursales_Productos (id_sucursal_producto)
);

CREATE TABLE IF NOT EXISTS Tipo_Ajustes (
    id_ajuste INT PRIMARY KEY AUTO_INCREMENT,
    id_cambio INT NOT NULL,
    id_sucursal_producto_ajuste INT NOT NULL,
    cantidad_ajuste INT NOT NULL ,
    FOREIGN KEY (id_cambio) REFERENCES Cambios_Sucursal (id_cambio),
    FOREIGN KEY (id_sucursal_producto_ajuste) REFERENCES Sucursales_Productos (id_sucursal_producto)
);



CREATE TABLE IF NOT EXISTS Estados_Pedidos (
    id_estado_pedido INT PRIMARY KEY AUTO_INCREMENT,
    estado_pedido ENUM('Confirmado','Procesado','Completado', 'Cancelado') UNIQUE
);

CREATE TABLE IF NOT EXISTS Pedidos (
    id_pedido INT PRIMARY KEY AUTO_INCREMENT,
    fecha_pedido DATETIME DEFAULT CURRENT_TIMESTAMP,
    id_estado_pedido INT NOT NULL,
    FOREIGN KEY (id_estado_pedido) REFERENCES Estados_Pedidos(id_estado_pedido)
);



CREATE TABLE IF NOT EXISTS Pedidos_Clientes (
    id_pedido_cliente INT PRIMARY KEY AUTO_INCREMENT,
    id_pedido INT NOT NULL UNIQUE,
    id_cliente INT NOT NULL,
    FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido),
    FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente)   
);


CREATE TABLE IF NOT EXISTS Tipos_Devoluciones (
    id_tipo_devoluciones INT PRIMARY KEY AUTO_INCREMENT,
    tipo_devolucion ENUM('Reembolso','Cambio') NOT NULL 
);


CREATE TABLE IF NOT EXISTS Devoluciones (
    id_devolucion INT PRIMARY KEY AUTO_INCREMENT,
    id_pedido INT NOT NULL,
    fecha_devolucion DATE NOT NULL DEFAULT CURRENT_DATE,
    FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido)
);

CREATE TABLE IF NOT EXISTS Pedidos_Detalles(
    id_pedido_detalle INT PRIMARY KEY AUTO_INCREMENT,
    id_sucursal INT NOT NULL,
    id_pedido INT NOT NULL,
    id_producto     INT NOT NULL,
    cantidad_producto  INT NOT NULL,
    FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido),
    FOREIGN KEY (id_sucursal, id_producto) REFERENCES Sucursales_Productos(id_sucursal, id_producto),
    UNIQUE (id_pedido, id_producto)
);    

CREATE TABLE IF NOT EXISTS Estados_Devoluciones (
    id_estado_devolucion INT PRIMARY KEY AUTO_INCREMENT,
    estado_devolucion ENUM('Pendiente', 'Completado','Autorizado','Rechazado') NOT NULL 
);

CREATE TABLE IF NOT EXISTS Devoluciones_Detalles (
    id_devolucion_detalle INT PRIMARY KEY AUTO_INCREMENT,
    id_devolucion INT NOT NULL,
    id_pedido_detalle INT NOT NULL,
    cantidad_devuelta INT NOT NULL,
    motivo_devolucion VARCHAR(200) NOT NULL,
    id_estado_devolucion INT NOT NULL,
    id_tipo_devoluciones INT NOT NULL,
    FOREIGN KEY (id_devolucion) REFERENCES Devoluciones(id_devolucion),
    FOREIGN KEY (id_pedido_detalle) REFERENCES Pedidos_Detalles(id_pedido_detalle),
    FOREIGN KEY (id_estado_devolucion) REFERENCES Estados_Devoluciones(id_estado_devolucion),
    FOREIGN KEY (id_tipo_devoluciones) REFERENCES Tipos_Devoluciones(id_tipo_devoluciones)
);


CREATE TABLE IF NOT EXISTS Clasificaciones_Reembolsos (
    id_clasificacion_reembolso INT PRIMARY KEY AUTO_INCREMENT,
    tipo_reembolso ENUM('Parcial', 'Extra','Total') NULL
);

CREATE TABLE IF NOT EXISTS Reembolsos (
    id_reembolso INT PRIMARY KEY AUTO_INCREMENT,
    id_pedido_detalle INT NOT NULL,
    monto_reembolso DECIMAL(10,2) NOT NULL,
    cantidad_reembolsada INT NOT NULL,
    id_clasificacion_reembolso INT NOT NULL,
    fecha_reembolso DATE NOT NULL DEFAULT CURRENT_DATE,
    motivo_reembolso VARCHAR(200) NOT NULL,
    FOREIGN KEY (id_pedido_detalle) REFERENCES Pedidos_Detalles(id_pedido_detalle),
    FOREIGN KEY (id_clasificacion_reembolso) REFERENCES Clasificaciones_Reembolsos(id_clasificacion_reembolso)
);

CREATE TABLE IF NOT EXISTS Reembolsos_Devolucion_Detalle (
    id_reembolso_devolucion_detalle INT PRIMARY KEY AUTO_INCREMENT,
    id_reembolso INT NOT NULL,
    id_devolucion_detalle INT NOT NULL,
    FOREIGN KEY (id_reembolso) REFERENCES Reembolsos(id_reembolso),
    FOREIGN KEY (id_devolucion_detalle) REFERENCES Devoluciones_Detalles(id_devolucion_detalle)
);


CREATE TABLE IF NOT EXISTS Facturas (
    id_factura INT PRIMARY KEY AUTO_INCREMENT,
    folio CHAR(36) NOT NULL UNIQUE,
    id_pedido INT NOT NULL UNIQUE,
    id_empresa INT NOT NULL,
    fecha_emision DATE NOT NULL DEFAULT CURRENT_DATE,
    subtotal DECIMAL(10,2) NOT NULL,
    impuestos DECIMAL(10,2) NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido),
    FOREIGN KEY (id_empresa) REFERENCES Empresas(id_empresa)
);

CREATE TABLE IF NOT EXISTS Estados_Facturas (
    id_estado_factura INT PRIMARY KEY AUTO_INCREMENT,
    id_factura INT NOT NULL,
    estado_factura ENUM('Pagada','Parcial') NOT NULL,
    fecha_estado_factura DATE NOT NULL DEFAULT CURRENT_DATE,
    UNIQUE (id_factura, estado_factura),
    FOREIGN KEY (id_factura) REFERENCES Facturas(id_factura)
);


CREATE TABLE IF NOT EXISTS Metodos_Pagos (
    id_metodo_pago INT PRIMARY KEY AUTO_INCREMENT,
    nombre_metodo_pago VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS Pagos (
    id_pago INT PRIMARY KEY AUTO_INCREMENT,
    id_factura INT NULL,
    id_pedido INT NOT NULL,
    fecha_pago DATE NOT NULL DEFAULT CURRENT_DATE,
    FOREIGN KEY (id_factura) REFERENCES Facturas(id_factura),
    FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido)
);


CREATE TABLE IF NOT EXISTS Montos_Pagos (
    id_montos_pago INT PRIMARY KEY AUTO_INCREMENT,
    id_metodo_pago INT NOT NULL,
    id_pago INT NOT NULL,
    monto_metodo_pago  DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (id_metodo_pago) REFERENCES Metodos_Pagos (id_metodo_pago),
    FOREIGN KEY (id_pago) REFERENCES Pagos(id_pago)
);

CREATE TABLE IF NOT EXISTS Imagenes_Productos (
    id_imagen_producto INT PRIMARY KEY AUTO_INCREMENT,
    id_producto INT NOT NULL,
    url_imagen VARCHAR(255) NOT NULL, -- file path or URL 
    fecha_carga DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES Productos(id_producto) 
        ON DELETE CASCADE -- If product is deleted, images are deleted
);

