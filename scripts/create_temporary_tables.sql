

CREATE TEMPORARY TABLE tmpTopProductos (
    top INT PRIMARY KEY AUTO_INCREMENT,
    nombre VARCHAR(150) NOT NULL,
    cantidad_vendida INT NOT NULL
);


CREATE TEMPORARY TABLE tmpMargenCat (
    id_tmp_margen INT AUTO_INCREMENT PRIMARY KEY,
    id_categoria INT NOT NULL,
    nombre_categoria VARCHAR(50) NOT NULL,
    ingreso_total DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    costo_total DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    margen_bruto DECIMAL(12, 2) NOT NULL DEFAULT 0.00
);


CREATE TEMPORARY TABLE tmpFacturacion(
    fecha_reporte DATE NOT NULL PRIMARY KEY,
    subtotal_facturado DECIMAL(10, 2) NULL,
    impuestos_facturados DECIMAL(10, 2) NULL,
    total_facturado DECIMAL(10, 2) NULL,
    conteo_facturas INT NULL
);


CREATE TEMPORARY TABLE tmpItemsDevolucion (
    id_tmp_devolucion_item INT AUTO_INCREMENT PRIMARY KEY,
    id_pedido INT NOT NULL,
    id_pedido_detalle INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad_a_devolver INT NOT NULL,
    motivo_devolucion VARCHAR(200) NOT NULL,
    id_tipo_devoluciones INT NOT NULL,
    fecha_registro DATETIME DEFAULT CURRENT_TIMESTAMP
);



