INSERT INTO Estados_Direcciones (estado_direccion) VALUES
('Aguascalientes'),
('Baja California'),
('Baja California Sur'),
('Campeche'),
('Coahuila'),
('Colima'),
('Chiapas'),
('Chihuahua'),
('Ciudad de México'),
('Durango'),
('Guanajuato'),
('Guerrero'),
('Hidalgo'),
('Jalisco'),
('México'),
('Michoacán'),
('Morelos'),
('Nayarit'),
('Nuevo León'),
('Oaxaca'),
('Puebla'),
('Querétaro'),
('Quintana Roo'),
('San Luis Potosí'),
('Sinaloa'),
('Sonora'),
('Tabasco'),
('Tamaulipas'),
('Tlaxcala'),
('Veracruz'),
('Yucatán'),
('Zacatecas');




INSERT INTO Municipios_Direcciones (municipio_direccion) VALUES
('Miguel Hidalgo'),
('Ecatepec'),
('Guadalajara'),
('Monterrey'),
('Naucalpan'),
('Puebla'),
('Veracruz'),
('Zapopan'),
('Querétaro'),
('León'),
('Cuajimalpa'),
('Culiacán'),
('Oaxaca'),
('San Nicolás'),
('Mérida'),
('Iztapalapa'),
('Chihuahua'),
('Tehuacán'),
('Tlaquepaque'),
('Toluca');


INSERT INTO Codigos_Postales (codigo_postal) VALUES
('11000'),
('55020'),
('44100'),
('64000'),
('54000'),
('72000'),
('91000'),
('45110'),
('76000'),
('37000'),
('05000'),
('80000'),
('68000'),
('66400'),
('97000'),
('09000'),
('31000'),
('75700'),
('45640'),
('50000');

INSERT INTO Codigos_Postales_Estados (id_cp, id_estado_direccion) VALUES
(1, 9),
(2, 15),
(3, 14),
(4, 19),
(5, 15),
(6, 21),
(7, 30),
(8, 14),
(9, 22),
(10, 11),
(11, 9),
(12, 25),
(13, 20),
(14, 19),
(15, 31),
(16, 9),
(17, 8),
(18, 21),
(19, 14),
(20, 15);

INSERT INTO Codigos_Postales_Municipios (id_cp, id_municipio_direccion) VALUES
(1, 1),
(2, 2),
(3, 3),
(4, 4),
(5, 5),
(6, 6),
(7, 7),
(8, 8),
(9, 9),
(10, 10),
(11, 11),
(12, 12),
(13, 13),
(14, 14),
(15, 15),
(16, 16),
(17, 17),
(18, 18),
(19, 19),
(20, 20);

INSERT INTO Direcciones (calle_direccion, numero_direccion, id_cp) VALUES
('Paseo de la Reforma', '234', 1),
('Colonia El Calvario', '45B', 2),
('Calle Pedro Moreno', '812', 3),
('Calle Padre Mier', '27A', 4),
('Av. Gustavo Baz', '150', 5),
('Calle 2 Sur', '118', 6),
('Av. Independencia', '530', 7),
('Av. Patria', '921', 8),
('Calle Corregidora', '77', 9),
('Blvd. López Mateos', '1045', 10),
('Av. Vasco de Quiroga', '56C', 11),
('Av. Álvaro Obregón', '889', 12),
('Calle Macedonio Alcalá', '310', 13),
('Av. Universidad', '214', 14),
('Paseo de Montejo', '1008', 15),
('Av. Ermita Iztapalapa', '45', 16),
('Av. Universidad', '670', 17),
('Calle 1 Poniente', '12A', 18),
('Calle Juárez', '340', 19),
('Av. Independencia', '999', 20);

INSERT INTO Empresas (nombre_empresa, rfc_empresa, id_direccion, correo_empresa) VALUES
('Auralisse Joyeria', 'AUL120915ABC', 1, 'contacto@auralisse.com');

INSERT INTO Generos (genero) VALUES
('Femenino'),
('Masculino'),
('No Binario'),
('Prefiere no especificar');



INSERT INTO Usuarios (
    nombre_usuario, nombre_primero, nombre_segundo,
    apellido_paterno, apellido_materno, rfc_usuario,
    telefono, correo, id_genero, id_direccion, contrasena,
    fecha_registro_usuario
) VALUES
-- Admin
('admin.auralisse', 'Carlos', 'Alberto', 'Ramírez', 'Mendoza', 
 'RAMC010203AB1', '5512345678', 'admin@auralisse.com', 2, 1,
 '$argon2id$v=19$m=65536,t=3,p=4$9IsSeqHqdAhQ/kxK6i7C8A$yj/dM+a6SLJCArVdq4n7b227a3pydjWEpFbijxBVJfI',
 '2023-01-10 09:12:45'),

-- Empleados (2–11)


-- Vendedores
('andrea.lopez', 'Andrea', 'Fernanda', 'López', 'García',
 'LOGA990715CD2', '8123456789', 'andrea.lopez@example.com', 1, 2,
 '$argon2id$v=19$m=65536,t=3,p=4$rGJdya7Q4y5IPmLjG62G8g$fn8V3Rre0O79WigpC9KoWR2AXxDIJ2OeGB6ZNtyZv3A',
 '2024-01-15 14:55:10'),

('mariana.gv', 'Mariana', NULL, 'González', 'Villalobos',
 'GOVM020304EF3', '3312345678', 'mariana.gv@example.com', 1, 3,
 '$argon2id$v=19$m=65536,t=3,p=4$2woruUsKaMjV7Ngm8oUxEQ$lcdiSxQMA0FpST6mwaW3kHRA/cJzLaKBHIuYgZ/nYBk',
 '2024-02-01 10:12:19'),

-- Gestores
('diego.santos', 'Diego', 'Alejandro', 'Santos', 'Hernández',
 'SAHD000101GH4', '4421234567', 'diego.santos@example.com', 2, 4,
 '$argon2id$v=19$m=65536,t=3,p=4$j6h4E6F9niHJN9nxKZFuvA$mHfuadWG7O85exB5ZxPu3rRQO0JV3jQ7LMeZMAxdaPU',
 '2024-02-07 17:22:48'),

('ximena.nv', 'Ximena', 'Valeria', 'Navarro', 'Flores',
 'NAFX050612IJ5', '5532124455', 'ximena.nv@example.com', 3, 5,
 '$argon2id$v=19$m=65536,t=3,p=4$aNAP2Kr6s6GfslV1txiT6g$aekhY7WfctaurMAbQh/75+VA1dHxVbwRF1N3FCxi7Zo',
 '2024-02-09 11:03:09'),

-- Analistas
('luis.mtz', 'Luis', 'Enrique', 'Martínez', 'Zavala',
 'MAZE971231KL6', '8187654321', 'luis.mtz@example.com', 2, 6,
 '$argon2id$v=19$m=65536,t=3,p=4$UoChnP144nt5PiHOiUId6g$JUlybaeVj0Va2MvtLhBn6IFTbvPSNcleXc7d6I5zPP4',
 '2024-02-13 09:48:55'),

('paola.ruiz', 'Paola', 'Denisse', 'Ruiz', 'Vega',
 'RUVP990215MN7', '5567891234', 'paola.ruiz@example.com', 1, 7,
 '$argon2id$v=19$m=65536,t=3,p=4$W8mQHhjQydKLY4rO23B9Ww$tnePeCrXkV87rFxq+7voVilV7mn1ZtBsDtSrdKuy8u0',
 '2024-02-13 11:09:31'),

-- Auditores
('jorge.sal', 'Jorge', 'Luis', 'Salazar', 'Ortiz',
 'SAOJ950820OP8', '6641239876', 'jorge.sal@example.com', 2, 8,
 '$argon2id$v=19$m=65536,t=3,p=4$QeITtlhcfr9C+Mw+bgjvEw$/aXEcQyo2NVWGHafB0vs2pz/LWfpemoIU7O2B4Gmles',
 '2024-02-15 13:44:20'),

('fernanda.vv', 'Fernanda', 'Sofía', 'Villarreal', 'Valdés',
 'VIVF030101QR9', '4426789988', 'fernanda.vv@example.com', 1, 9,
 '$argon2id$v=19$m=65536,t=3,p=4$vy1npQUzsql5u6S/dKQ2Uw$PZueGsriNvtR6FM2uwr3ssLi4j4VhLaoop2ZWpO48XQ',
 '2024-02-18 16:21:05'),

-- Vendedores otra vez
('ricardo.lr', 'Ricardo', 'Iván', 'Lara', 'Rosas',
 'LARR010202ST1', '4771239988', 'ricardo.lr@example.com', 2, 10,
 '$argon2id$v=19$m=65536,t=3,p=4$6gGUzSP9alW7NY5ObGU+xw$0+Vlm1wWym3TzGMMQo/vaUA270e7YB0mQ3mSdYa5IYU',
 '2024-02-20 08:45:13'),

('sofia.mg', 'Sofía', 'María', 'Mendoza', 'Gómez',
 'MEGS041110UV2', '5588776655', 'sofia.mg@example.com', 1, 11,
 '$argon2id$v=19$m=65536,t=3,p=4$m/RdqAq19CyzSr+q3fsmaA$MY456lmTBqckeyYdur926eIclITjkPtiySDFAARiOtM',
 '2024-02-20 10:12:47'),

-- Clientes

('alejandro.vh', 'Alejandro', 'Héctor', 'Vega', 'Hurtado',
 'VEHA930703WX3', '6672213344', 'alejandro.vh@example.com', 2, 12,
 '$argon2id$v=19$m=65536,t=3,p=4$wMPhV4hZsL4pNesH2a5ahg$pjsuOIu9zdVzUPtwRwKuIIMmpX+NHX/9/v/0J2iC0aw',
 '2024-02-21 09:33:12'),

('valeria.oax', 'Valeria', 'Itzel', 'Ortiz', 'Álvarez',
 'OAAV020506YZ4', '9511237788', 'valeria.oax@example.com', 1, 13,
 '$argon2id$v=19$m=65536,t=3,p=4$JKIB3qO9KlJqrynaA0QKrw$0yMnyW4oiIb4CMJ19+rSCtn0GYPD5OWkYvHpIl1YKc0',
 '2024-02-22 15:07:56'),

('eduardo.sg', 'Eduardo', 'Daniel', 'Sánchez', 'García',
 'SAGE000909AB5', '8182203344', 'eduardo.sg@example.com', 2, 14,
 '$argon2id$v=19$m=65536,t=3,p=4$p183FQYvISI7KJ80kzXKsA$YIFtFCM3rpsut66xARnHc63ObGVLQGtKeuHRUr9vKiA',
 '2024-02-23 12:41:33'),

('maria.mer', 'María', 'José', 'Medina', 'Rosas',
 'MERM051212CD6', '9991123456', 'maria.mer@example.com', 1, 15,
 '$argon2id$v=19$m=65536,t=3,p=4$lulLRxpIpQOAdvSVXPDu7g$DkMTzwvkjBDDdxQoAnqBIgtWb5HZ9TXiuWUXxu7r194',
 '2024-02-23 18:20:11'),

('antonio.izt', 'Antonio', 'Javier', 'Ibarra', 'Téllez',
 'IBTA990101EF7', '5511002233', 'antonio.izt@example.com', 2, 16,
 '$argon2id$v=19$m=65536,t=3,p=4$dPVoXIlN8U/Q8SMow5QaKg$lSSZ4Dh/tm90BOTjX2GQUEA3mxRZViRYZuWM43yxRmA',
 '2024-02-24 09:46:58'),

('salma.ch', 'Salma', 'Renata', 'Chávez', 'Haro',
 'CHHS030405GH8', '6148872211', 'salma.ch@example.com', 1, 17,
 '$argon2id$v=19$m=65536,t=3,p=4$JJGZ5rU5NDOCar0AqxxgjA$DOtOSMNnyIt3GLkS8ROhmwQ04rfOJHskhwd0w4cS/+o',
 '2024-02-24 11:19:45'),

('roberto.th', 'Roberto', 'Miguel', 'Torres', 'Hernández',
 'TOHR940811IJ9', '2381123344', 'roberto.th@example.com', 2, 18,
 '$argon2id$v=19$m=65536,t=3,p=4$gmx0YKWkq7kGxZEglPLibQ$xNedWPLR3wFI+jpHyRf+ZKvRjYQwPNn9G1lmwQxxMu8',
 '2024-02-25 14:10:18'),

('julieta.tq', 'Julieta', 'Aranza', 'Tovar', 'Quintero',
 'TOQJ050303KL1', '3312009988', 'julieta.tq@example.com', 1, 19,
 '$argon2id$v=19$m=65536,t=3,p=4$dLSxa9/UjwGQXoke2yl77w$AFV3haBtaJhFTZWfEzU9gl+PuBBGHoMccQVYbf49qkw',
 '2024-02-26 08:58:29'),

('raul.tol', 'Raúl', 'Andrés', 'Treviño', 'Lozano',
 'TRLR960202MN2', '7229981234', 'raul.tol@example.com', 2, 20,
 '$argon2id$v=19$m=65536,t=3,p=4$mSN2gTWEXrJdKq3e4sfm0A$ossQVhsFx7VIF/gT6Gmf5sIsRDN8IjVICq7k2KERi4I',
 '2024-02-26 17:21:10'),

('karla.crm', 'Karla', 'Soledad', 'Cruz', 'Ramírez',
 'CRRK990101AB3', '5512349988', 'karla.crm@example.com', 1, 4,
 '$argon2id$v=19$m=65536,t=3,p=4$XEjrUnbSWMHLaRM5C0OpeQ$Kroz7eCTwRhq8s412iMQdDq1jZDrs3aHToUQ/lTWuew',
 '2024-02-27 09:15:22'),

('oscar.mn', 'Oscar', 'Manuel', 'Montoya', 'Nunez',
 'MONO981212CD4', '8125673344', 'oscar.mn@example.com', 2, 6,
 '$argon2id$v=19$m=65536,t=3,p=4$s5Kr/Ph2iHXqtvzvG+CBFw$Yq0ekDhQ6+s8AFM1c+/dXNWRuzleRHKZBBhxWXsYtmk',
 '2024-02-27 11:47:39'),

('jimena.rv', 'Jimena', 'Alejandra', 'Rivas', 'Valle',
 'RIVJ030303EF5', '3311457788', 'jimena.rv@example.com', 1, 8,
 '$argon2id$v=19$m=65536,t=3,p=4$AtqM/FtCyh1duyuFOhaUKA$lV4EKLqrtDKXZ793NGrHvUnYWbMsMN3vA6xqtTa33Xo',
 '2024-02-28 10:05:11'),

('eduardo.pl', 'Eduardo', 'Luis', 'Pineda', 'Lopez',
 'PILE970707GH6', '4426671100', 'eduardo.pl@example.com', 2, 12,
 '$argon2id$v=19$m=65536,t=3,p=4$1Z8thX1dUv8qmxRkVLT1fg$QiPw1z3bKk/2DABue2JltX05XwmLj96XigTruNGLk5c',
 '2024-02-28 15:22:54'),

('valeria.sz', 'Valeria', 'Noemi', 'Sanchez', 'Zuniga',
 'SAZV040404IJ7', '5511902234', 'valeria.sz@example.com', 1, 15,
 '$argon2id$v=19$m=65536,t=3,p=4$bKW97uPUZkokR80fbBTCNQ$pcls7uof5voeH63qXRcWSlA5lTpZf+byGii/0XDRGDY',
 '2024-02-29 09:41:37'),

('raul.hg', 'Raul', 'Hector', 'Hernandez', 'Gutierrez',
 'HEGR960606KL8', '7225567890', 'raul.hg@example.com', 2, 18,
 '$argon2id$v=19$m=65536,t=3,p=4$FNPUGmgPshtz79zuOA0tXw$42vwbUnn+w73coq67jA54g2U812yVrw3uMQa1njFeRA',
 '2024-02-29 17:03:02');




INSERT INTO Roles (nombre_rol, descripcion_roles) VALUES
('Admin', 'Tiene acceso total al sistema: puede crear, editar o eliminar cualquier registro.'),
('Vendedor', 'Gestiona pedidos, clientes y facturas. Puede aplicar descuentos o cancelar pedidos bajo políticas.'),
('Gestor de Sucursal', 'Controla existencias, reingresos y movimientos de stock. Supervisa devoluciones aprobadas.'),
('Analista Financiero', 'Supervisa pagos, facturación y márgenes de ganancia. Acceso a reportes económicos.'),
('Auditor', 'Revisa operaciones, pedidos, facturas y logs sin modificarlos. Acceso de solo lectura.'),
('Cliente', 'Usuario externo que puede registrarse, consultar el catálogo, generar pedidos y ver sus facturas y devoluciones.');


INSERT INTO Sucursales (nombre_sucursal, id_direccion, activo_sucursal) VALUES
('Sucursal Reforma', 1, 1),
('Sucursal Ecatepec Centro', 2, 1),
('Sucursal Guadalajara Centro', 3, 1),
('Sucursal Monterrey Centro', 4, 1),
('Sucursal Naucalpan Industrial', 5, 1),
('Sucursal Puebla Zócalo', 6, 1),
('Sucursal Veracruz Puerto', 7, 1),
('Sucursal Zapopan Patria', 8, 1),
('Sucursal Querétaro Alameda', 9, 1),
('Sucursal León Centro Max', 10, 1);

INSERT INTO Roles_Sucursales (id_roles, id_sucursal) VALUES
(2, 1),   
(2, 2),  
(3, 3),   
(3, 4),   
(4, 5),   
(4, 6),   
(5, 7),  
(5, 8),  
(2, 9),  
(2, 10); 

INSERT INTO Usuarios_Roles_Sucursales (id_usuario, id_roles_sucursal, activo_usuario_rol_sucursal) VALUES
(2, 1, 1),    
(3, 2, 1),   
(4, 3, 1),   
(5, 4, 1),    
(6, 5, 1),   
(7, 6, 1),  
(8, 7, 1),    
(9, 8, 1),    
(10, 9, 1),   
(11, 10, 1); 

INSERT INTO Usuarios_Roles (id_usuario, id_roles, id_usuario_rol_sucursal, activo_usuario_rol) VALUES
(1, 1, NULL, 1),    -- Admin global

-- Empleados (2–11)
(2, 2, 1, 1),       -- Vendedor (suc 1)
(3, 2, 2, 1),       -- Vendedor (suc 2)
(4, 3, 3, 1),       -- Gestor   (suc 3)
(5, 3, 4, 1),       -- Gestor   (suc 4)
(6, 4, 5, 1),       -- Analista (suc 5)
(7, 4, 6, 1),       -- Analista (suc 6)
(8, 5, 7, 1),       -- Auditor  (suc 7)
(9, 5, 8, 1),       -- Auditor  (suc 8)
(10, 2, 9, 1),      -- Vendedor (suc 9)
(11, 2, 10, 1),     -- Vendedor (suc 10)

-- Clientes (sin sucursal, rol 6)
(12, 6, NULL, 1),
(13, 6, NULL, 1),
(14, 6, NULL, 1),
(15, 6, NULL, 1),
(16, 6, NULL, 1),
(17, 6, NULL, 1),
(18, 6, NULL, 1),
(19, 6, NULL, 1),
(20, 6, NULL, 1),
(21, 6, NULL, 1),
(22, 6, NULL, 1),
(23, 6, NULL, 1),
(24, 6, NULL, 1),
(25, 6, NULL, 1),
(26, 6, NULL, 1);




INSERT INTO Clasificaciones (nombre_clasificacion, descuento_clasificacion, compra_min, compra_max, descripcion_clasificacion, ultima_actualizacion) VALUES
('Regular', 0, 0.00, 9999.99, 'Clientes nuevos o con bajo gasto acumulado', '2023-10-01 00:00:00'),
('Premium', 10, 10000.00, 29999.99, 'Gasto entre 10,000 y < 30,000', '2023-10-01 00:00:00'),
('VIP', 20, 30000.00, NULL, 'Gasto igual o mayor a 30,000', '2023-10-01 00:00:00'),
('Empleado', 30, NULL, NULL, 'Descuento por ser empleado de la joyería', '2023-10-01 00:00:00');

INSERT INTO Clientes (id_clasificacion, id_usuario) VALUES
(1, 12),
(1, 13),
(1, 14),
(1, 15),
(1, 16),
(1, 17),
(1, 18),
(1, 19),
(1, 20),
(1, 21),
(1, 22),
(1, 23),
(1, 24),
(1, 25),
(1, 26);



INSERT INTO Categorias (nombre_categoria, activo_categoria) VALUES
('Anillos', TRUE),
('Collares', TRUE),
('Pulseras', TRUE),
('Aretes', TRUE),
('Relojes', TRUE);


INSERT INTO Generos_Productos (genero_producto) VALUES
('Mujer'),
('Hombre'),
('Unisex');


INSERT INTO Modelos (nombre_producto, id_categoria, id_genero_producto) VALUES
('Anillo Brillante Luna', 1, 1),
('Collar Esfera de Plata', 2, 1),
('Pulsera Elegancia Rosa', 3, 1),
('Aretes Destello Dorado', 4, 1),
('Reloj Acero Nocturno', 5, 2),
('Anillo Forjado Imperial', 1, 2),
('Collar Cruz Minimalista', 2, 3),
('Pulsera Cadenas Urbano', 3, 2),
('Aretes Perla Clásica', 4, 1),
('Reloj Vintage Chronos', 5, 3), 
('Anillo Estrella Polar', 1, 1),
('Anillo Tritón de Acero', 1, 2),
('Collar Aura Celeste', 2, 1),
('Collar Dual Infinito', 2, 3),
('Pulsera Trenzado Real', 3, 2),
('Pulsera Perla Lunar', 3, 1),
('Aretes Flor de Nieve', 4, 1),
('Aretes Lux Geométrico', 4, 3),
('Reloj Oceanic Silver', 5, 2),
('Reloj Elegance Rose Gold', 5, 1);


INSERT IGNORE INTO Sku (sku) VALUES
('AUR-001A'),
('AUR-001B'),
('AUR-001C'),
('AUR-002A'),
('AUR-002B'),
('AUR-003A'),
('AUR-003B'),
('AUR-004A'),
('AUR-004B'),
('AUR-005A'),
('AUR-006A'),
('AUR-007A'),
('AUR-007B'),
('AUR-008A'),
('AUR-009A'),
('AUR-010A'),
('AUR-011A'),
('AUR-012A'),
('AUR-012B'),
('AUR-013A'),
('AUR-014A'),
('AUR-015A'),
('AUR-015B'),
('AUR-016A'),
('AUR-017A');


INSERT IGNORE INTO Materiales (material) VALUES
('Oro'),
('Plata');



INSERT IGNORE INTO Productos (
    id_sku,
    id_modelo,
    id_material,
    precio_unitario,
    descuento_producto,
    costo_unitario,
    fecha_actualizacion_producto,
    activo_producto
) VALUES
(1,  1, 1, 2500.00,  5, 1500.00, '2025-01-01 10:00:00', TRUE),
(2,  1, 2, 2350.00, 10, 1450.00, '2025-01-02 11:10:00', TRUE),
(3,  1, 1, 2650.00,  0, 1600.00, '2025-01-03 12:20:00', TRUE),

(4,  2, 1, 3200.00,  0, 1900.00, '2025-01-04 09:15:00', TRUE),
(5,  2, 2, 2950.00,  5, 1750.00, '2025-01-05 14:30:00', TRUE),

(6,  3, 2, 1850.00,  0, 1150.00, '2025-01-06 16:45:00', TRUE),
(7,  3, 1, 2100.00,  5, 1300.00, '2025-01-07 08:50:00', TRUE),

(8,  4, 1, 2200.00,  5, 1350.00, '2025-01-08 09:05:00', TRUE),
(9,  5, 1, 4800.00, 10, 3000.00, '2025-01-09 13:40:00', TRUE),

(10, 6, 2, 2750.00,  0, 1650.00, '2025-01-10 10:55:00', TRUE),
(11, 7, 2, 1950.00,  0, 1200.00, '2025-01-11 15:12:00', TRUE),
(12, 8, 1, 2150.00,  5, 1320.00, '2025-01-12 11:33:00', TRUE),
(13, 9, 1, 2600.00,  0, 1550.00, '2025-01-13 16:44:00', TRUE),

(14,10, 2, 5300.00, 15, 3450.00, '2025-01-14 09:18:00', TRUE),
(15,11, 1, 2450.00,  0, 1480.00, '2025-01-15 17:25:00', TRUE),

(16,12, 1, 2620.00,  5, 1570.00, '2025-01-16 12:11:00', TRUE),
(17,13, 2, 2050.00,  0, 1220.00, '2025-01-17 14:22:00', TRUE),
(18,14, 2, 2020.00,  0, 1210.00, '2025-01-18 15:09:00', TRUE),

(19,15, 1, 2850.00,  5, 1700.00, '2025-01-19 09:33:00', TRUE),
(20,16, 2, 1950.00,  0, 1180.00, '2025-01-20 18:46:00', FALSE),

(21,17, 1, 1780.00,  0, 1070.00, '2025-01-21 11:58:00', TRUE),
(22,18, 2, 1980.00,  0, 1160.00, '2025-01-22 13:07:00', TRUE),
(23,19, 1, 2200.00,  5, 1350.00, '2025-01-23 15:27:00', TRUE),
(24,20, 2, 4100.00, 10, 2600.00, '2025-01-24 08:45:00', TRUE),
(25,10, 1, 5550.00, 20, 3600.00, '2025-01-25 17:55:00', TRUE);



INSERT IGNORE INTO Tallas_Productos (talla, id_producto) VALUES
(5, 1), (6, 1), (7, 1), (8, 1), (9, 1),
(5, 2), (6, 2), (7, 2), (8, 2), (9, 2),
(5, 3), (6, 3), (7, 3), (8, 3),
(6,10), (7,10), (8,10),
(5,15), (6,15), (7,15), (8,15), (9,15),
(6,16), (7,16), (8,16), (9,16);



INSERT IGNORE INTO Productos_Oro_Kilataje (id_producto, kilataje) VALUES
(1,  '18K'),
(3,  '14K'),
(4,  '14K'),
(7,  '18K'),
(8,  '10K'),
(9,  '18K'),
(12, '14K'),
(13, '18K'),
(15, '18K'),
(16, '24K'),
(19, '18K'),
(21, '14K'),
(23, '24K'),
(25, '18K');

INSERT IGNORE INTO Productos_Plata_Ley (id_producto, ley) VALUES
(2,  '925'),
(5,  '925'),
(6,  '900'),
(10, '950'),
(11, '925'),
(14, '830'),
(17, '925'),
(18, '800'),
(20, '925'),
(22, '950'),
(24, '999');

INSERT IGNORE INTO Sucursales_Productos (id_sucursal, id_producto, stock_ideal, stock_actual, stock_maximo) VALUES
(1, 1, 10, 8, 15),
(1, 2, 10, 9, 15),
(1, 3, 8, 7, 12),
(1, 4, 6, 5, 10),
(1, 5, 5, 4, 9),

(2, 6, 7, 6, 11),
(2, 7, 7, 5, 11),
(2, 8, 6, 5, 10),
(2, 9, 5, 4, 9),
(2,10,4, 3, 7),

(3,11,6, 5, 10),
(3,12,7, 6, 11),
(3,13,6, 5, 10),
(3,14,5, 4, 9),
(3,15,5, 4, 9),

(4,16,6, 5, 10),
(4,17,7, 6, 11),
(4,18,6, 5, 10),
(4,19,5, 4, 9),
(4,20,4, 3, 7),

(5,21,5, 4, 9),
(5,22,5, 4, 9),
(5,23,6, 5, 10),
(5,24,4, 3, 7),
(5,25,3, 2, 6);

INSERT IGNORE INTO Tipos_Cambios (tipo_cambio, descripcion) VALUES
('Entrada', 'Movimiento que incrementa el inventario por compra o reingreso'),
('Salida', 'Movimiento que disminuye el inventario por venta o transferencia'),
('Ajuste', 'Corrección manual del inventario por auditoría o error detectado');

INSERT IGNORE INTO Cambios_Sucursal (id_usuario_rol, id_tipo_cambio, motivo_cambio, fecha_cambio) VALUES
-- ENTRADAS (10)
(1, 1, 'Recepción de mercancía de proveedor',        '2025-02-01 09:25:10'),
(2, 1, 'Reingreso por devolución del cliente',       '2025-02-02 10:15:40'),
(3, 1, 'Compra de nuevos modelos de anillos',        '2025-02-03 11:45:22'),
(4, 1, 'Entrada por regularización de inventario',   '2025-02-04 14:12:10'),
(5, 1, 'Reabastecimiento de pulseras básicas',       '2025-02-05 13:35:09'),
(2, 1, 'Entrada de mercancía por temporada',         '2025-02-06 10:58:10'),
(3, 1, 'Reingreso por venta cancelada',              '2025-02-07 16:40:22'),
(4, 1, 'Entrada por devolución corporativa',         '2025-02-08 12:01:17'),
(5, 1, 'Reposición de stock crítico',                '2025-02-09 09:48:33'),
(1, 1, 'Entrada extraordinaria aprobada por dirección','2025-02-10 08:55:11'),

-- SALIDAS (10)
(2, 2, 'Salida por venta mostrador',                 '2025-02-11 12:42:55'),
(3, 2, 'Salida por venta en línea',                  '2025-02-12 15:15:22'),
(4, 2, 'Salida por traslado a sucursal León',        '2025-02-13 10:50:28'),
(5, 2, 'Salida por venta a cliente premium',         '2025-02-14 13:07:14'),
(1, 2, 'Salida por préstamo para sesión fotográfica','2025-02-15 08:10:44'),
(2, 2, 'Salida por venta mayorista',                 '2025-02-16 14:58:21'),
(3, 2, 'Salida por exhibición en escaparate especial','2025-02-17 10:11:10'),
(4, 2, 'Salida por venta diaria',                    '2025-02-18 18:20:14'),
(5, 2, 'Salida para promoción de San Valentín',       '2025-02-19 12:30:49'),
(1, 2, 'Salida por venta urgente',                   '2025-02-20 09:13:33'),

-- AJUSTES (10)
(2, 3, 'Ajuste por daño en exhibición',              '2025-02-21 11:17:44'),
(3, 3, 'Ajuste por conteo cíclico mensual',          '2025-02-22 17:55:38'),
(4, 3, 'Ajuste por error de captura',                '2025-02-23 10:28:19'),
(5, 3, 'Ajuste por merma identificada',              '2025-02-24 13:14:55'),
(1, 3, 'Ajuste autorizado por dirección',            '2025-02-25 08:40:09'),
(2, 3, 'Ajuste por pérdida reportada',               '2025-02-26 15:11:49'),
(3, 3, 'Ajuste por inventario físico',               '2025-02-27 09:58:33'),
(4, 3, 'Ajuste por producto sin código',             '2025-02-28 11:47:27'),
(5, 3, 'Ajuste por variación de stock',              '2025-03-01 12:33:12'),
(1, 3, 'Ajuste final por cierre mensual',            '2025-03-02 16:20:55');

INSERT IGNORE INTO Tipo_Entradas (id_cambio, id_sucursal_producto_destino, cantidad_entrada) VALUES
(1,  1, 5),
(2,  2, 3),
(3,  6, 4),
(4,  7, 6),
(5, 11, 3),
(6, 12, 5),
(7, 16, 2),
(8, 17, 4),
(9, 21, 3),
(10, 23, 5);

INSERT IGNORE INTO Tipo_Salidas (id_cambio, id_sucursal_producto_origen, cantidad_salida) VALUES
(11, 1, 3),
(12, 2, 4),
(13, 3, 2),
(14, 6, 3),
(15, 7, 2),
(16,10, 2),
(17,12, 3),
(18,15, 2),
(19,18, 2),
(20,25, 1);

INSERT IGNORE INTO Tipo_Ajustes (id_cambio, id_sucursal_producto_ajuste, cantidad_ajuste) VALUES
(21, 4, 5),
(22, 5, 4),
(23, 8, 5),
(24, 9, 4),
(25,13, 5),
(26,14, 4),
(27,19, 4),
(28,20, 3),
(29,22, 4),
(30,24, 3);






INSERT IGNORE INTO Estados_Pedidos (estado_pedido) VALUES
('Confirmado'),
('Procesado'),
('Completado'),
('Cancelado');

INSERT IGNORE INTO Pedidos (fecha_pedido, id_estado_pedido) VALUES
('2025-11-05 11:22:10', 1),
('2025-11-06 14:10:45', 1),
('2025-11-07 09:55:33', 1),
('2025-11-08 16:20:12', 1),
('2025-11-09 10:47:05', 1),
('2025-11-10 13:55:29', 1),
('2025-11-11 15:33:41', 1),
('2025-11-12 08:40:50', 1),
('2025-11-13 12:19:15', 1),
('2025-11-14 17:28:39', 1),

('2025-11-15 10:03:58', 2),
('2025-11-16 11:59:21', 3),
('2025-11-17 18:45:00', 2),
('2025-11-18 09:24:33', 4),
('2025-11-19 14:55:27', 3);

INSERT IGNORE INTO Pedidos_Clientes (id_pedido, id_cliente) VALUES
(1,  1),
(2,  2),
(3,  3),
(4,  4),
(5,  5),
(6,  6),
(7,  7),
(8,  8),
(9,  9),
(10, 10),
(11, 11),
(12, 12),
(13, 13),
(14, 14),
(15, 15);




INSERT IGNORE INTO Tipos_Devoluciones (tipo_devolucion) VALUES
('Reembolso'),
('Cambio');

-- Update orders to follow proper state flow: Confirmado -> Procesado -> Completado
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 1 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 2 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 3 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 4 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 5 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 6 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 7 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 8 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 9 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 2 WHERE id_pedido = 10 AND id_estado_pedido = 1;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 1 AND id_estado_pedido = 2;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 2 AND id_estado_pedido = 2;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 3 AND id_estado_pedido = 2;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 4 AND id_estado_pedido = 2;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 5 AND id_estado_pedido = 2;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 6 AND id_estado_pedido = 2;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 7 AND id_estado_pedido = 2;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 8 AND id_estado_pedido = 2;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 9 AND id_estado_pedido = 2;
UPDATE Pedidos SET id_estado_pedido = 3 WHERE id_pedido = 10 AND id_estado_pedido = 2;


INSERT IGNORE INTO Devoluciones (id_pedido, fecha_devolucion) VALUES
(1,  '2025-11-07'),
(2,  '2025-11-08'),
(3,  '2025-11-09'),
(4,  '2025-11-10'),
(5,  '2025-11-11'),
(6,  '2025-11-12'),
(7,  '2025-11-13'),
(8,  '2025-11-14'),
(9,  '2025-11-15'),
(10, '2025-11-16');







INSERT IGNORE INTO Pedidos_Detalles (
    id_sucursal,
    id_pedido,
    id_producto,
    cantidad_producto
) VALUES
(1, 1, 1, 2),
(1, 1, 2, 1),

(1, 2, 3, 2),
(1, 2, 4, 1),

(1, 3, 5, 1),

(2, 3, 6, 2),
(2, 3, 7, 1),

(2, 4, 8, 2),
(2, 4, 9, 1),

(2, 5, 10, 1),
(3, 5, 11, 2),

(3, 6, 12, 2),
(3, 6, 13, 1),

(3, 7, 14, 1),
(3, 7, 15, 1),

(4, 8, 16, 2),
(4, 8, 17, 2),

(4, 9, 18, 1),
(4, 9, 19, 1),

(4, 10, 20, 1),

(5, 10, 21, 1),
(5, 11, 22, 2),
(5, 11, 23, 1),

(5, 12, 24, 1),
(5, 13, 25, 1);




INSERT IGNORE INTO Estados_Devoluciones (estado_devolucion) VALUES
('Pendiente'),
('Completado'),
('Autorizado'),
('Rechazado');

INSERT IGNORE INTO Devoluciones_Detalles (
    id_devolucion,
    id_pedido_detalle,
    cantidad_devuelta,
    motivo_devolucion,
    id_estado_devolucion,
    id_tipo_devoluciones
) VALUES
(1, 1, 1, 'Talla incorrecta', 2, 2),
(2, 3, 1, 'Producto diferente al solicitado', 1, 1),
(3, 6, 1, 'No era lo esperado', 2, 1),
(4, 8, 1, 'Daño en empaque', 1, 2),
(5, 11, 1, 'Color distinto al mostrado', 2, 1),
(6, 13, 1, 'Cliente cambió de opinión', 2, 1),
(7, 15, 1, 'Defecto visual', 1, 2),
(8, 17, 1, 'No coincide con la fotografía', 2, 1),
(9, 19, 1, 'Daño en transporte', 1, 2),
(10, 21, 1, 'Regalo repetido', 2, 1);



INSERT IGNORE INTO Clasificaciones_Reembolsos (tipo_reembolso) VALUES
('Parcial'),
('Extra'),
('Total');

INSERT IGNORE INTO Reembolsos (
    id_pedido_detalle,
    monto_reembolso,
    cantidad_reembolsada,
    id_clasificacion_reembolso,
    fecha_reembolso,
    motivo_reembolso
) VALUES
(1,  350.00, 1, 3, '2025-11-09', 'Devolución total del producto'),
(3,  120.00, 1, 1, '2025-11-10', 'Reembolso parcial por daño menor'),
(6,  500.00, 1, 3, '2025-11-11', 'Producto defectuoso, reembolso total'),
(8,  80.00,  1, 1, '2025-11-12', 'Diferencia de precio por promoción'),
(11, 150.00, 1, 2, '2025-11-13', 'Compensación por retraso en el envío'),
(13, 200.00, 1, 1, '2025-11-14', 'Reembolso parcial por inconformidad'),
(15, 320.00, 1, 3, '2025-11-15', 'Reembolso total por producto equivocado'),
(17, 50.00,  1, 2, '2025-11-16', 'Bonificación extra por inconvenientes'),
(19, 100.00, 1, 1, '2025-11-17', 'Reembolso parcial por detalle estético'),
(21, 450.00, 1, 3, '2025-11-18', 'Reembolso total por falla del producto');

INSERT IGNORE INTO Reembolsos_Devolucion_Detalle (id_reembolso, id_devolucion_detalle) VALUES
(1, 1),
(3, 3),
(5, 5),
(6, 6),
(8, 8),
(10, 10);


INSERT IGNORE INTO Facturas (folio, id_pedido, id_empresa, subtotal, impuestos, total) VALUES
(UUID(), 1, 1, 4400.00, 704.00, 5104.00),
(UUID(), 2, 1, 4100.00, 656.00, 4756.00),
(UUID(), 3, 1, 6200.00, 992.00, 7192.00),
(UUID(), 4, 1, 4800.00, 768.00, 5568.00),
(UUID(), 5, 1, 5400.00, 864.00, 6264.00),
(UUID(), 6, 1, 5300.00, 848.00, 6148.00),
(UUID(), 7, 1, 3350.00, 536.00, 3886.00),
(UUID(), 8, 1, 6000.00, 960.00, 6960.00),
(UUID(), 9, 1, 3550.00, 568.00, 4118.00),
(UUID(), 10, 1, 3600.00, 576.00, 4176.00);


INSERT IGNORE INTO Estados_Facturas (id_factura, estado_factura, fecha_estado_factura) VALUES
(1, 'Pagada',  '2025-11-05'),
(2, 'Pagada',  '2025-11-06'),
(3, 'Parcial', '2025-11-07'),
(5, 'Pagada',  '2025-11-09'),
(6, 'Pagada',  '2025-11-10'),
(9, 'Pagada',  '2025-11-13');



INSERT IGNORE INTO Metodos_Pagos (nombre_metodo_pago) VALUES
('Tarjeta Crédito'),
('Efectivo'),
('Transferencia Bancaria');

INSERT IGNORE INTO Pagos (id_factura, id_pedido, fecha_pago) VALUES
(1,  1, '2025-11-05'),
(2,  2, '2025-11-06'),
(3,  3, '2025-11-07'),
(5,  5, '2025-11-09'),
(6,  6, '2025-11-10'),
(9,  9, '2025-11-13');


INSERT IGNORE INTO Montos_Pagos (id_metodo_pago, id_pago, monto_metodo_pago) VALUES
(1, 1, 5104),
(2, 2, 4756),(1, 3, 3000),
(3, 4, 6264),
(1, 5, 6148),
(2, 6, 4118);
