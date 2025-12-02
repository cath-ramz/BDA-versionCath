from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, session, flash, jsonify
from flask_mysqldb import MySQL
from datetime import timedelta, datetime, date
from config import DevelopmentConfig
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
import MySQLdb.cursors
import json
import traceback

ph = PasswordHasher()

app = Flask(__name__)
# Usar configuración de desarrollo
app.config.from_object(DevelopmentConfig)

# Configuración de MySQL
mysql = MySQL(app)
app.permanent_session_lifetime = timedelta(days=7)

# ----------------------------------
# Decoradores de sesión y roles
# ----------------------------------
def login_requerido(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        if "user_id" not in session:
            # Si es una ruta API, devolver JSON en lugar de redirigir
            if request.path.startswith('/api/'):
                return jsonify({
                    'success': False,
                    'error': 'Debes iniciar sesión para acceder a esta sección',
                    'require_login': True
                }), 401
            # Para rutas normales, redirigir a login
            flash("Debes iniciar sesión para acceder a esta sección", "warning")
            return redirect(url_for("login"))
        return func(*args, **kwargs)
    return wrapper

def requiere_rol(*roles_permitidos):
    """
    Permite acceso solo si el usuario tiene uno de los roles indicados.
    Cada panel/ruta debe especificar exactamente qué roles pueden acceder.
    Usa session['role'] que llenas en el login.
    Comparación insensible a mayúsculas/minúsculas.
    
    Ejemplo: @requiere_rol('Admin', 'Vendedor') permite ambos roles
    """
    def decorador(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            if "user_id" not in session:
                flash("Debes iniciar sesión para acceder a esta sección", "warning")
                return redirect(url_for("login"))

            rol_usuario = (session.get("role") or "").lower()
            roles_lower = [r.lower() for r in roles_permitidos]

            # Verificar si el rol del usuario está en los roles permitidos (ignorando mayúsculas)
            if rol_usuario in roles_lower:
                return func(*args, **kwargs)
            flash("No tienes permisos para acceder a esta sección", "danger")
            return redirect(url_for("catalogo"))
        return wrapper
    return decorador

# Contexto global para templates - hacer disponible el objeto user
@app.context_processor
def inject_user():
    user = None
    if 'user_id' in session:
        user = {
            'id': session.get('user_id'),
            'user_name': session.get('username'),
            'role': session.get('role'),
            'full_name': session.get('full_name', 'Usuario')
        }
    return dict(user=user)

# (Decoradores viejos, por si los usas en otro lado)
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

def role_required(*roles):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if 'user_id' not in session:
                return redirect(url_for('login'))
            if session.get('role') not in roles:
                return render_template('403.html', message='No tienes permisos para acceder a esta sección'), 403
            return f(*args, **kwargs)
        return decorated_function
    return decorator

# ==================== RUTAS PÚBLICAS ====================

@app.route('/')
def catalogo():
    """Catálogo público de productos - Página de inicio"""
    categoria_seleccionada = request.args.get('categoria', '')
    
    try:
        import MySQLdb.cursors
        # Usar DictCursor para acceder a los campos por nombre en el template
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener todas las categorías activas usando SP categoriasActivas - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('categoriasActivas', [])
        categorias = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener productos activos usando SP productosCatalogo - SOLO SP, NO SQL EMBEBIDO
        categoria_param = categoria_seleccionada if categoria_seleccionada else None
        cursor.callproc('productosCatalogo', [categoria_param])
        productos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Depuración: imprimir algunos productos para verificar que los descuentos se obtengan correctamente
        if productos:
            print(f"[DEBUG] Primeros 3 productos:")
            for i, p in enumerate(productos[:3]):
                print(f"  Producto {i+1}: id={p.get('id_producto')}, nombre={p.get('nombre')}, "
                      f"precio_original={p.get('precio_original')}, descuento={p.get('descuento_producto')}, "
                      f"precio={p.get('precio')}")
        
        cursor.close()
    except Exception as e:
        print(f"Error cargando productos: {e}")
        import traceback
        traceback.print_exc()
        productos = []
        categorias = []
    
    return render_template('catalogo.html', productos=productos, categorias=categorias, categoria_seleccionada=categoria_seleccionada)

# ==================== API PARA REGISTRO DE CLIENTES ====================

@app.route('/api/clientes/crear', methods=['POST'])
def api_crear_cliente():
    """Endpoint para crear cliente usando SOLO SP clienteCrear - SIN SQL EMBEBIDO"""
    try:
        data = request.get_json()

        # Extraer y validar datos requeridos
        nombre_usuario = data.get('nombre_usuario', '').strip()
        nombre_primero = data.get('nombre_primero', '').strip()
        
        nombre_segundo = data.get('nombre_segundo')
        if nombre_segundo and isinstance(nombre_segundo, str):
            nombre_segundo = nombre_segundo.strip()
        else:
            nombre_segundo = None

        apellido_paterno = data.get('apellido_paterno', '').strip()
        apellido_materno = (data.get('apellido_materno') or '').strip() or None
        rfc_usuario = None  # No se solicita en el formulario
        telefono = None  # No se solicita en el formulario
        correo = data.get('correo', '').strip()
        contrasena = data.get('contrasena', '').strip()
        nombre_genero = (data.get('nombre_genero') or '').strip() or None
        calle_direccion = None  # No se solicita en el formulario
        numero_direccion = None  # No se solicita en el formulario
        codigo_postal = None  # No se solicita en el formulario
        id_clasificacion = None  # No se solicita en el formulario, se asignará automáticamente como cliente

        # Validaciones básicas
        if not nombre_usuario:
            return jsonify({'error': 'El nombre de usuario es requerido'}), 400
        if not nombre_primero:
            return jsonify({'error': 'El nombre es requerido'}), 400
        if not apellido_paterno:
            return jsonify({'error': 'El apellido paterno es requerido'}), 400
        if not correo:
            return jsonify({'error': 'El correo es requerido'}), 400
        if not contrasena:
            return jsonify({'error': 'La contraseña es requerida'}), 400
        if len(contrasena) < 6:
            return jsonify({'error': 'La contraseña debe tener al menos 6 caracteres'}), 400
        
        # Hashear la contraseña con Argon2 antes de guardarla
        contrasena_hash = ph.hash(contrasena)
        
        cursor = mysql.connection.cursor()
        
        cursor.callproc('clienteCrear', [
            nombre_usuario,
            nombre_primero,
            nombre_segundo,
            apellido_paterno,
            apellido_materno,
            rfc_usuario,
            telefono,
            correo,
            contrasena_hash,  # Enviar el hash en lugar de la contraseña en texto plano
            nombre_genero,
            calle_direccion,
            numero_direccion,
            codigo_postal,
            id_clasificacion
        ])
        
        id_cliente = None
        try:
            resultado = cursor.fetchone()
            if resultado:
                if isinstance(resultado, dict):
                    id_cliente = resultado.get('id_nuevo_cliente', 0)
                else:
                    id_cliente = resultado[0] if resultado else 0
                print(f"Cliente creado con ID: {id_cliente}")
        except Exception as e:
            print(f"Error leyendo resultado del SP: {e}")
        
        if not id_cliente or id_cliente == 0:
            print("No se pudo obtener ID del SP, consultando MAX(id_cliente)...")
            cursor.callproc('sp_cliente_max_id', [])
            resultado_max = cursor.fetchone()
            while cursor.nextset():
                pass
            id_cliente = resultado_max.get('id_cliente', 0) if resultado_max else 0
            print(f"ID obtenido de MAX: {id_cliente}")
        
        while cursor.nextset():
            pass
        
        mysql.connection.commit()
        
        # Obtener el usuario recién creado con su rol para iniciar sesión automáticamente
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        try:
            cursor.callproc('sp_usuario_obtener_rol_por_username', [nombre_usuario])
            resultado_usuario = cursor.fetchall()
            
            # Limpiar resultados adicionales
            while cursor.nextset():
                pass
            
            if resultado_usuario and len(resultado_usuario) > 0:
                usuario = resultado_usuario[0]
                
                # Guardar carrito antes de limpiar sesión (si existe)
                carrito_anterior = session.get('carrito', [])
                
                # Crear sesión automáticamente
                session.clear()
                session['user_id'] = usuario['id_usuario']
                session['username'] = usuario['nombre_usuario']
                session['full_name'] = usuario['nombre_completo']
                session['role'] = usuario['nombre_rol']
                session['id_usuario_rol'] = usuario['id_usuario_rol']
                
                # Compatibilidad con decoradores viejos
                session['usuario_id'] = usuario['id_usuario']
                session['roles'] = [usuario['nombre_rol']]
                
                # Restaurar carrito si existía antes del registro
                if carrito_anterior:
                    session['carrito'] = carrito_anterior
                
                session.permanent = True
                
                cursor.close()
                
                return jsonify({
                    'success': True,
                    'mensaje': 'Cliente registrado exitosamente',
                    'id_cliente': id_cliente,
                    'session_created': True,
                    'redirect_url': url_for('cliente_perfil')
                })
            else:
                cursor.close()
                
                # Si no se pudo obtener el usuario, redirigir al login
                return jsonify({
                    'success': True,
                    'mensaje': 'Cliente registrado exitosamente. Por favor, inicia sesión.',
                    'id_cliente': id_cliente,
                    'session_created': False,
                    'redirect_url': url_for('login')
                })
        except Exception as e:
            cursor.close()
            import traceback
            print(traceback.format_exc(), flush=True)
            
            # Si hay error, redirigir al login
            return jsonify({
                'success': True,
                'mensaje': 'Cliente registrado exitosamente. Por favor, inicia sesión.',
                'id_cliente': id_cliente,
                'session_created': False,
                'redirect_url': url_for('login')
            })
    except Exception as e:
        import traceback
        error_msg = f"Error creando cliente: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        error_str = str(e)
        mensaje_usuario = 'Error al registrar el cliente.'
        
        if 'Error:' in error_str:
            parts = error_str.split('Error:', 1)
            if len(parts) > 1:
                mensaje_usuario = parts[1].strip()
        elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
            if ':' in error_str:
                mensaje_usuario = error_str.split(':', 1)[-1].strip()
        elif 'Duplicate entry' in error_str or 'duplicado' in error_str.lower():
            if 'correo' in error_str.lower() or 'email' in error_str.lower():
                mensaje_usuario = 'El correo electrónico ya está registrado.'
            elif 'nombre_usuario' in error_str.lower() or 'usuario' in error_str.lower():
                mensaje_usuario = 'El nombre de usuario ya está en uso.'
            elif 'rfc' in error_str.lower():
                mensaje_usuario = 'El RFC ya está registrado.'
            else:
                mensaje_usuario = 'Ya existe un registro con estos datos.'
        
        return jsonify({
            'success': False,
            'error': str(e),
            'mensaje': mensaje_usuario
        }), 500

# ==================== RUTAS DEL CARRITO ====================

@app.route('/api/carrito/agregar', methods=['POST'])
def agregar_al_carrito():
    """Agregar producto al carrito"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No se recibieron datos'}), 400
            
        id_producto = data.get('id_producto')
        cantidad = data.get('cantidad', 1)
        
        if not id_producto:
            return jsonify({'error': 'ID de producto requerido'}), 400
        
        cursor = mysql.connection.cursor()
        try:
            cursor.callproc('producto_info_carrito', [id_producto])
            producto = cursor.fetchone()
            while cursor.nextset():
                pass
        finally:
            cursor.close()

        if not producto:
            return jsonify({'error': 'Producto no encontrado o no está activo'}), 404
        
        if hasattr(producto, 'keys'):
            producto_dict = dict(producto)
        else:
            producto_dict = producto
        
        # Obtener precio y descuento del producto
        precio_unitario = float(producto_dict.get('precio', 0))
        descuento = float(producto_dict.get('descuento_producto', 0) or 0)
        
        # Aplicar descuento al precio: precio - precio*descuento (el precio ya incluye IVA)
        precio_con_descuento = precio_unitario - (precio_unitario * descuento / 100)
        
        if 'carrito' not in session:
            session['carrito'] = []
        
        carrito = session.get('carrito', [])
        producto_existente = next((item for item in carrito if item.get('id_producto') == id_producto), None)
        
        if producto_existente:
            producto_existente['cantidad'] += cantidad
            # Actualizar el precio en caso de que haya cambiado el descuento
            producto_existente['precio'] = precio_con_descuento
        else:
            carrito.append({
                'id_producto': int(id_producto),
                'nombre': str(producto_dict.get('nombre', 'Producto sin nombre')),
                'precio': precio_con_descuento,  # Precio con descuento aplicado
                'sku': str(producto_dict.get('sku', 'N/A')),
                'cantidad': int(cantidad)
            })
        
        session['carrito'] = carrito
        session.modified = True
        
        total_items = sum(item.get('cantidad', 0) for item in carrito)
        
        return jsonify({
            'success': True,
            'mensaje': 'Producto agregado al carrito',
            'total_items': total_items
        })
    except Exception as e:
        import traceback
        error_trace = traceback.format_exc()
        print(f"Error agregando al carrito: {str(e)}\n{error_trace}")
        return jsonify({
            'error': str(e),
            'mensaje': 'Error al agregar producto al carrito. Verifique que el producto exista y esté activo.'
        }), 500

@app.route('/api/carrito/obtener')
def obtener_carrito():
    """Obtener todos los productos del carrito"""
    try:
        # Verificar si hay una sesión de usuario autenticado
        # Si no hay user_id en la sesión, devolver 401 para indicar que se requiere login
        # PERO solo si el carrito está vacío o si se está intentando hacer checkout
        # Para la página principal, permitir obtener el carrito sin autenticación
        # pero cuando se intenta hacer checkout, se verificará la autenticación
        
        carrito = session.get('carrito', [])
        total = sum(item['precio'] * item['cantidad'] for item in carrito)
        total_items = sum(item['cantidad'] for item in carrito)
        
        return jsonify({
            'carrito': carrito,
            'total': total,
            'total_items': total_items
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/carrito/eliminar', methods=['POST'])
def eliminar_del_carrito():
    """Eliminar producto del carrito"""
    try:
        data = request.get_json()
        id_producto = data.get('id_producto')
        
        if not id_producto:
            return jsonify({'error': 'ID de producto requerido'}), 400
        
        if 'carrito' not in session:
            return jsonify({'error': 'Carrito vacío'}), 400
        
        carrito = session['carrito']
        carrito = [item for item in carrito if item['id_producto'] != id_producto]
        session['carrito'] = carrito
        session.modified = True
        
        total = sum(item['precio'] * item['cantidad'] for item in carrito)
        total_items = sum(item['cantidad'] for item in carrito)
        
        return jsonify({
            'success': True,
            'total': total,
            'total_items': total_items
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/carrito/actualizar', methods=['POST'])
def actualizar_cantidad_carrito():
    """Actualizar cantidad de un producto en el carrito"""
    try:
        data = request.get_json()
        id_producto = data.get('id_producto')
        cantidad = data.get('cantidad', 1)
        
        if not id_producto or cantidad < 1:
            return jsonify({'error': 'Datos inválidos'}), 400
        
        if 'carrito' not in session:
            return jsonify({'error': 'Carrito vacío'}), 400
        
        carrito = session['carrito']
        producto = next((item for item in carrito if item['id_producto'] == id_producto), None)
        
        if producto:
            producto['cantidad'] = cantidad
            session['carrito'] = carrito
            session.modified = True
        
        total = sum(item['precio'] * item['cantidad'] for item in carrito)
        total_items = sum(item['cantidad'] for item in carrito)
        
        return jsonify({
            'success': True,
            'total': total,
            'total_items': total_items
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/carrito/vaciar', methods=['POST'])
def vaciar_carrito():
    """Vaciar el carrito completamente"""
    try:
        session['carrito'] = []
        session.modified = True
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/carrito/restaurar', methods=['POST'])
def restaurar_carrito():
    """Restaurar carrito desde sessionStorage después del login"""
    try:
        # Verificar que el usuario esté autenticado
        if 'user_id' not in session:
            return jsonify({'error': 'Debe iniciar sesión para restaurar el carrito'}), 401
        
        data = request.get_json()
        carrito = data.get('carrito', [])
        if not carrito or not isinstance(carrito, list):
            return jsonify({'error': 'Carrito inválido'}), 400
        
        # Validar que cada item tenga los campos necesarios
        for item in carrito:
            if 'id_producto' not in item or 'cantidad' not in item or 'precio' not in item:
                return jsonify({'error': 'Formato de carrito inválido'}), 400
        
        # Restaurar el carrito en la sesión
        session['carrito'] = carrito
        session.modified = True
        
        total = sum(item['precio'] * item['cantidad'] for item in carrito)
        total_items = sum(item['cantidad'] for item in carrito)
        return jsonify({
            'success': True,
            'total': total,
            'total_items': total_items,
            'mensaje': 'Carrito restaurado exitosamente'
        })
    except Exception as e:
        import traceback
        print(f"Error restaurando carrito: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/carrito/checkout', methods=['POST'])
def api_checkout_carrito():
    """Endpoint para procesar checkout del carrito: crear pedido y preparar pago"""
    try:
        if 'user_id' not in session:
            return jsonify({
                'error': 'Debe iniciar sesión para realizar el pago',
                'require_login': True
            }), 401
        
        carrito = session.get('carrito', [])
        if not carrito or len(carrito) == 0:
            return jsonify({'error': 'El carrito está vacío'}), 400
        
        # Obtener parámetro opcional para solicitar factura
        data = request.get_json() if request.is_json else {}
        solicitar_factura = data.get('solicitar_factura', False)
        
        id_usuario = session.get('user_id')
        
        cursor = mysql.connection.cursor()
        
        cursor.execute("""
            CREATE TEMPORARY TABLE IF NOT EXISTS TmpPedidos (
                id_tmp_pedido INT AUTO_INCREMENT PRIMARY KEY,
                fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
                id_usuario INT NULL
            )
        """)
        cursor.execute("""
            CREATE TEMPORARY TABLE IF NOT EXISTS TmpItems_Pedido (
                id_tmp_item INT AUTO_INCREMENT PRIMARY KEY,
                id_producto INT NOT NULL,
                cantidad_producto INT NOT NULL,
                id_tmp_pedido INT NOT NULL
            )
        """)
        
        cursor.callproc('sp_tmp_pedido_insertar', [id_usuario])
        resultado_tmp = cursor.fetchone()
        while cursor.nextset():
            pass
        id_tmp_pedido = resultado_tmp.get('id_tmp_pedido', 0) if resultado_tmp else cursor.lastrowid
        
        for item in carrito:
            id_producto = item.get('id_producto')
            cantidad = item.get('cantidad', 1)
            if id_producto and cantidad > 0:
                cursor.callproc('sp_tmp_item_pedido_insertar', [id_producto, cantidad, id_tmp_pedido])
                while cursor.nextset():
                    pass
        
        try:
            cursor.callproc('pedidoCrear', [id_tmp_pedido])
            # Consumir todos los resultados del SP
            while cursor.nextset():
                pass
        except Exception as sp_error:
            # Cerrar cursor y hacer rollback antes de procesar el error
            try:
                cursor.close()
            except:
                pass
            try:
                mysql.connection.rollback()
            except:
                pass
            # Re-lanzar el error para que sea manejado en el bloque except externo
            raise sp_error
        
        cursor.callproc('sp_pedido_max_id', [])
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        id_pedido = resultado.get('id_pedido', 0) if resultado else 0
        
        if not id_pedido:
            cursor.close()
            return jsonify({'error': 'No se pudo crear el pedido'}), 500
        

        # Obtener la clasificación del cliente y su descuento
        cursor.execute("""
            SELECT COALESCE(cl.descuento_clasificacion, 0) AS descuento_clasificacion
            FROM Clientes c
            LEFT JOIN Clasificaciones cl ON c.id_clasificacion = cl.id_clasificacion
            WHERE c.id_usuario = %s
        """, (id_usuario,))
        clasificacion_result = cursor.fetchone()
        descuento_clasificacion = float(clasificacion_result.get('descuento_clasificacion', 0) or 0) if clasificacion_result else 0
        
        # Calcular el total del pedido aplicando descuentos de productos (sumando los detalles)
        # Nota: El precio del producto ya incluye IVA, y se debe aplicar el descuento: precio - precio*descuento
        cursor.execute("""
            SELECT COALESCE(SUM((pr.precio_unitario - (pr.precio_unitario * COALESCE(pr.descuento_producto, 0) / 100)) * pd.cantidad_producto), 0) AS total_pedido
            FROM Pedidos_Detalles pd
            JOIN Productos pr ON pd.id_producto = pr.id_producto
            WHERE pd.id_pedido = %s
        """, (id_pedido,))
        total_result = cursor.fetchone()
        total_pedido = float(total_result.get('total_pedido', 0) or 0) if total_result else 0
        
        # Aplicar descuento de clasificación del cliente al total
        # total_final = total_pedido - (total_pedido * descuento_clasificacion / 100)
        total_con_descuento_clasificacion = total_pedido - (total_pedido * descuento_clasificacion / 100) if descuento_clasificacion > 0 else total_pedido
        # El precio ya incluye IVA y se aplicó el descuento de producto, ahora también se aplica el descuento de clasificación
        
        # Crear factura solo si se solicita
        id_factura = None
        total_factura = None
        
        if solicitar_factura:
            try:
                cursor.callproc('pedidoFacturar', [id_pedido])
                # Consumir todos los resultados del SP
                while cursor.nextset():
                    pass
                
                # Obtener la factura creada usando SP
                cursor.callproc('sp_factura_por_pedido', [id_pedido])
                factura = cursor.fetchone()
                while cursor.nextset():
                    pass
                
                if factura:
                    id_factura = factura.get('id_factura')
                    total_factura_sin_desc = float(factura.get('total', 0))
                    
                    # Aplicar descuento de clasificación al total de la factura
                    if descuento_clasificacion > 0:
                        total_factura = total_factura_sin_desc - (total_factura_sin_desc * descuento_clasificacion / 100)
                        # Actualizar el total de la factura con el descuento aplicado
                        cursor.callproc('sp_factura_actualizar_total_descuento', [id_factura, total_factura])
                        while cursor.nextset():
                            pass
                    else:
                        total_factura = total_factura_sin_desc
                    
            except Exception as sp_error:
                error_msg = str(sp_error)
                # Si ya tiene factura, intentar obtenerla
                if 'ya tiene una factura' in error_msg.lower():
                    try:
                        cursor.callproc('sp_factura_por_pedido', [id_pedido])
                        factura = cursor.fetchone()
                        while cursor.nextset():
                            pass
                        if factura:
                            id_factura = factura.get('id_factura')
                            total_factura_sin_desc = float(factura.get('total', 0))
                            
                            # Aplicar descuento de clasificación al total de la factura
                            if descuento_clasificacion > 0:
                                total_factura = total_factura_sin_desc - (total_factura_sin_desc * descuento_clasificacion / 100)
                                # Actualizar el total de la factura con el descuento aplicado
                                cursor.callproc('sp_factura_actualizar_total_descuento', [id_factura, total_factura])
                                while cursor.nextset():
                                    pass
                            else:
                                total_factura = total_factura_sin_desc
                    except:
                        pass
                else:
                    # Si es otro error y se solicitó factura, reportarlo
                    cursor.close()
                    mysql.connection.rollback()
                    return jsonify({'error': f'Error al crear factura: {error_msg}'}), 500
        
        mysql.connection.commit()
        cursor.close()
        
        # Vaciar el carrito después de crear el pedido exitosamente
        session['carrito'] = []
        session.modified = True
        
        # Retornar respuesta - siempre mostrar modal de pago, con o sin factura
        # Si hay factura, usar su total, si no, usar el total del pedido con descuento de clasificación
        total_a_pagar = total_factura if (id_factura and total_factura) else total_con_descuento_clasificacion
        
        return jsonify({
            'success': True,
            'id_pedido': id_pedido,
            'id_factura': id_factura,  # Puede ser None
            'total': total_a_pagar,
            'descuento_clasificacion': descuento_clasificacion,
            'total_sin_descuento_clasificacion': total_pedido,  # Para mostrar en el modal si hay descuento
            'mensaje': 'Pedido creado exitosamente. Proceda con el pago.'
        })
    except Exception as e:
        import traceback
        error_str = str(e)
        error_msg = f"Error en checkout: {error_str}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Asegurar que el cursor esté cerrado y se haga rollback
        try:
            if 'cursor' in locals():
                cursor.close()
        except:
            pass
        try:
            mysql.connection.rollback()
        except:
            pass
        
        # Detectar si falta RFC u otros datos
        # El error puede venir como "(1644, 'ERROR_FALTA_RFC')" o como "ERROR_FALTA_RFC"
        # También puede venir como MySQLdb.OperationalError con args[1]
        error_message = error_str
        if hasattr(e, 'args') and len(e.args) > 0:
            # Intentar extraer el mensaje de args
            for arg in e.args:
                if isinstance(arg, str) and 'ERROR_' in arg:
                    error_message = arg
                    break
                elif isinstance(arg, (tuple, list)) and len(arg) > 1:
                    # Si es una tupla como (1644, 'ERROR_FALTA_RFC')
                    if isinstance(arg[1], str) and 'ERROR_' in arg[1]:
                        error_message = arg[1]
                        break
        
        # Normalizar el mensaje para buscar el error (convertir a mayúsculas)
        error_normalized = (error_str + ' ' + error_message).upper()
        
        if 'ERROR_FALTA_RFC' in error_normalized:
            return jsonify({
                'error': 'ERROR_FALTA_RFC',
                'mensaje': 'Para completar tu compra, necesitamos que completes tu información personal. Te redirigiremos a una página donde podrás agregar tu RFC, dirección y teléfono.',
                'require_complete_data': True
            }), 400
        elif 'ERROR_FALTA_DIRECCION' in error_normalized:
            return jsonify({
                'error': 'ERROR_FALTA_DIRECCION',
                'mensaje': 'Para completar tu compra, necesitamos tu dirección de entrega. Te redirigiremos a una página donde podrás agregarla.',
                'require_complete_data': True
            }), 400
        elif 'ERROR_FALTA_TELEFONO' in error_normalized:
            return jsonify({
                'error': 'ERROR_FALTA_TELEFONO',
                'mensaje': 'Para completar tu compra, necesitamos tu número de teléfono. Te redirigiremos a una página donde podrás agregarlo.',
                'require_complete_data': True
            }), 400
        elif 'ERROR_SIN_CLIENTE' in error_normalized:
            # Usuario no autenticado - redirigir al login
            return jsonify({
                'error': 'ERROR_SIN_CLIENTE',
                'mensaje': 'Debe iniciar sesión para realizar el pago.',
                'require_login': True
            }), 401
        elif 'ERROR_STOCK_INSUFICIENTE' in error_str or 'Stock insuficiente' in error_str:
            return jsonify({
                'error': 'ERROR_STOCK_INSUFICIENTE',
                'mensaje': 'Lo sentimos, algunos productos en tu carrito no tienen suficiente inventario disponible en este momento. Por favor, revisa las cantidades o intenta más tarde.'
            }), 400
        elif "Column 'id_sucursal' cannot be null" in error_str or "cannot be null" in error_str:
            return jsonify({
                'error': 'ERROR_SUCURSAL_NULL',
                'mensaje': 'Error al asignar sucursal. Por favor, verifica que el producto esté asignado a una sucursal activa.'
            }), 500
        
        # Mostrar el error real para debugging
        return jsonify({
            'error': str(e),
            'mensaje': f'Error al procesar el checkout: {error_str}. Verifique la consola del servidor para más detalles.'
        }), 500

# ==================== RUTAS DE AUTENTICACIÓN ====================
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = (request.form.get('username') or '').strip()
        password = (request.form.get('password') or '').strip()

        if not username or not password:
            return render_template('login.html', error='Usuario y contraseña son requeridos')

        try:
            # Obtener usuario desde el SP
            cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
            cur.callproc('sp_usuario_obtener_rol_por_username', [username])
            resultado = cur.fetchall()
            cur.close()

            if not resultado:
                return render_template('login.html', error='Usuario no encontrado o sin rol activo')

            usuario = resultado[0]
            hash_bd = usuario['contrasena']

            # Verificación Argon2
            try:
                ph.verify(hash_bd, password)
            except VerifyMismatchError:
                return render_template('login.html', error='Contraseña incorrecta')

            # ==============================
            #       CREAR SESIÓN
            # ==============================
            # Guardar carrito antes de limpiar sesión (si existe)
            carrito_anterior = session.get('carrito', [])
            session.clear()

            session['user_id']        = usuario['id_usuario']
            session['username']       = usuario['nombre_usuario']
            session['full_name']      = usuario['nombre_completo']
            session['role']           = usuario['nombre_rol']
            session['id_usuario_rol'] = usuario['id_usuario_rol']

            # Compatibilidad con decoradores viejos
            session['usuario_id']     = usuario['id_usuario']
            session['roles']          = [usuario['nombre_rol']]

            # Restaurar carrito si existía antes del login
            if carrito_anterior:
                session['carrito'] = carrito_anterior

            session.permanent = True
            flash('Sesión iniciada correctamente', 'info')

            # ==============================
            #     REDIRECCIÓN SEGÚN ROL
            # ==============================
            rol = (usuario['nombre_rol'] or '').lower()

            if rol == 'admin' or rol == 'administrador':
                return redirect(url_for('admin'))

            if rol == 'vendedor':
                return redirect(url_for('ventas'))

            if rol == 'gestor de sucursal' or rol == 'inventarios':
                return redirect(url_for('inventario'))

            if rol == 'analista financiero' or rol == 'finanzas':
                return redirect(url_for('finanzas'))

            if rol == 'auditor':
                return redirect(url_for('auditor'))

            # Cliente o rol no reconocido → dashboard del cliente
            if rol == 'cliente':
                try:
                    return redirect(url_for('cliente_dashboard'))
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    return redirect(url_for('catalogo'))
            
            # Si no tiene rol conocido → catálogo público
            return redirect(url_for('catalogo'))

        except Exception as e:
            import traceback
            traceback.print_exc()
            return render_template('login.html', error=f'Error iniciando sesión: {str(e)}')

    # GET
    return render_template('login.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    """Página de registro de nuevos clientes"""
    if request.method == 'GET':
        try:
            import MySQLdb.cursors
            cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
            cursor.callproc('sp_clasificaciones_lista', [])
            clasificaciones = cursor.fetchall()
            while cursor.nextset():
                pass
            cursor.callproc('sp_generos_lista', [])
            generos = cursor.fetchall()
            while cursor.nextset():
                pass
            cursor.close()
            return render_template('register.html', clasificaciones=clasificaciones, generos=generos)
        except Exception as e:
            import traceback
            print(f"Error cargando datos de registro: {str(e)}\n{traceback.format_exc()}")
            return render_template('register.html', clasificaciones=[], generos=[])
    
    return redirect(url_for('login'))

@app.route('/logout')
def logout():
    """Cerrar sesión"""
    session.clear()
    flash('Sesión cerrada correctamente', 'info')
    return redirect(url_for('catalogo'))

# ==================== RUTAS PRINCIPALES (por rol) ====================
@app.route('/dashboard')
@login_requerido
def dashboard():
    """
    Router central: según el rol en sesión,
    redirige al panel que toque.
    """
    rol = (session.get('role') or '').lower()

    if rol in ('admin', 'administrador'):
        return redirect(url_for('admin'))

    if rol == 'inventarios':
        return redirect(url_for('admin_inventario'))

    if rol == 'ventas':
        return redirect(url_for('admin_pedidos'))

    if rol == 'finanzas':
        return redirect(url_for('admin_facturas'))

    if rol == 'auditor':
        return redirect(url_for('admin_reportes'))

    # Si no tiene rol conocido → catálogo público
    return redirect(url_for('catalogo'))
    
@app.route('/admin')
@login_requerido
@requiere_rol('Admin')
def admin():
    """Panel de administración - solo para rol Admin"""
    return render_template('admin_dashboard.html')

@app.route('/admin/pedidos')
@login_requerido
@requiere_rol('Admin')
def admin_pedidos():
    """Página de gestión de pedidos para rol Vendedor"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('ventas_pedidos_lista', [None, 'DESC'])
        pedidos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.callproc('ventas_estados_pedidos', [])
        estados_disponibles = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('ventas_pedidos.html', pedidos=pedidos, estados_disponibles=estados_disponibles)
    except Exception as e:
        import traceback
        print(f"Error cargando pedidos admin: {str(e)}\n{traceback.format_exc()}")
        return render_template('ventas_pedidos.html', pedidos=[], estados_disponibles=[])

def decode_row(row):
    """Función auxiliar para decodificar una fila de la base de datos"""
    if not row:
        return None
    
    decoded_row = {}
    for key, value in row.items():
        if value is None:
            decoded_row[key] = None
        elif isinstance(value, bytes):
            try:
                decoded_row[key] = value.decode('utf-8')
            except UnicodeDecodeError:
                try:
                    decoded_row[key] = value.decode('latin-1')
                except:
                    decoded_row[key] = value.decode('utf-8', errors='ignore')
        elif isinstance(value, str):
            decoded_row[key] = value
        else:
            decoded_row[key] = value
    return decoded_row

@app.route('/admin/facturas')
@login_requerido
@requiere_rol('Admin')
def admin_facturas():
    """Gestión de facturas para Analista Financiero usando SOLO SP admin_facturas_lista - SIN SQL EMBEBIDO"""
    try:
        # Obtener parámetros de filtro de la URL
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or None
        fecha_fin = request.args.get('fecha_fin', '').strip() or None
        busqueda = request.args.get('busqueda', '').strip() or None
        
        # Convertir fechas de string a date si están presentes
        fecha_inicio_date = None
        fecha_fin_date = None
        
        if fecha_inicio:
            try:
                fecha_inicio_date = datetime.strptime(fecha_inicio, '%Y-%m-%d').date()
            except ValueError:
                fecha_inicio_date = None
        
        if fecha_fin:
            try:
                fecha_fin_date = datetime.strptime(fecha_fin, '%Y-%m-%d').date()
            except ValueError:
                fecha_fin_date = None
        
        # Configurar charset en la conexión antes de crear el cursor
        try:
            mysql.connection.ping()
        except:
            # Si la conexión está cerrada, se reconectará automáticamente al hacer la siguiente query
            pass
        
        # Verificar si el stored procedure existe y cuántas facturas hay
        import MySQLdb.cursors
        cursor_check = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor_check.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")
        
        cursor_check.execute("""
            SELECT ROUTINE_NAME 
            FROM information_schema.ROUTINES 
            WHERE ROUTINE_SCHEMA = DATABASE() 
            AND ROUTINE_NAME = 'admin_facturas_lista'
        """)
        sp_exists = cursor_check.fetchone()       
        cursor_check.callproc('sp_facturas_count', [])
        total_facturas = cursor_check.fetchone()
        while cursor_check.nextset():
            pass
        print(f"[DEBUG finanzas_facturas] Total facturas en BD: {total_facturas.get('total', 0) if total_facturas else 0}")
        
        # Verificar si hay facturas con pedidos asociados
        cursor_check.execute("""
            SELECT COUNT(*) as total 
            FROM Facturas f 
            INNER JOIN Pedidos p ON f.id_pedido = p.id_pedido
        """)
        facturas_con_pedidos = cursor_check.fetchone()
        print(f"[DEBUG finanzas_facturas] Facturas con pedidos asociados: {facturas_con_pedidos.get('total', 0) if facturas_con_pedidos else 0}")
        cursor_check.close()
        
        # Crear un cursor nuevo para el stored procedure usando DictCursor
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")
        
        # Obtener facturas usando SP admin_facturas_lista - SOLO SP, NO SQL EMBEBIDO
        facturas = []
        try:
            print(f"[DEBUG finanzas_facturas] Llamando SP admin_facturas_lista con: fecha_inicio={fecha_inicio_date}, fecha_fin={fecha_fin_date}, busqueda={busqueda}")
            # Llamar al stored procedure
            cursor.callproc('admin_facturas_lista', [fecha_inicio_date, fecha_fin_date, busqueda])
            
            # Obtener el primer result set
            facturas_raw = cursor.fetchall()
            print(f"[DEBUG finanzas_facturas] Facturas obtenidas del SP: {len(facturas_raw)}")
            
            # Consumir todos los result sets adicionales
            while cursor.nextset():
                pass
            
            # Convertir los datos y manejar codificación
            for row in facturas_raw:
                try:
                    decoded_row = decode_row(row)
                    if decoded_row:
                        # Asegurar que fecha_emision sea date si viene como string
                        if 'fecha_emision' in decoded_row and decoded_row['fecha_emision']:
                            if isinstance(decoded_row['fecha_emision'], str):
                                try:
                                    decoded_row['fecha_emision'] = datetime.strptime(decoded_row['fecha_emision'], '%Y-%m-%d').date()
                                except:
                                    try:
                                        decoded_row['fecha_emision'] = datetime.strptime(decoded_row['fecha_emision'], '%Y-%m-%d %H:%M:%S').date()
                                    except:
                                        pass
                        facturas.append(decoded_row)
                except Exception as decode_error:
                    import traceback
                    print(f"[ERROR finanzas_facturas] Error decodificando fila: {str(decode_error)}")
                    traceback.print_exc()
            
            print(f"[DEBUG finanzas_facturas] Facturas después de decodificar: {len(facturas)}")
            
            if len(facturas) == 0 and total_facturas and total_facturas.get('total', 0) > 0:
                print(f"[DEBUG finanzas_facturas] No se obtuvieron facturas del SP pero hay {total_facturas.get('total', 0)} en BD. Usando fallback SQL.")
                cursor.callproc('sp_facturas_lista_filtrada', [fecha_inicio_date, fecha_fin_date])
                facturas_fallback = cursor.fetchall()
                for row in facturas_fallback:
                    decoded_row = decode_row(row)
                    if decoded_row:
                        facturas.append(decoded_row)
                        
        except Exception as sp_error:
            import traceback
            error_msg = f"[ERROR] Error ejecutando stored procedure: {str(sp_error)}\n{traceback.format_exc()}"
            print(error_msg)
            facturas = []
        
        cursor.close()
        
        return render_template(
            'facturas.html', 
            facturas=facturas,
            fecha_inicio=fecha_inicio or '',
            fecha_fin=fecha_fin or '',
            busqueda=busqueda or '',
            route_name='admin_facturas'
        )
    except UnicodeDecodeError as e:
        import traceback
        error_msg = f"Error de codificación cargando facturas: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Obtener parámetros de filtro de la URL para el fallback
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or None
        fecha_fin = request.args.get('fecha_fin', '').strip() or None
        busqueda = request.args.get('busqueda', '').strip() or None
        
        fecha_inicio_date = None
        fecha_fin_date = None
        
        if fecha_inicio:
            try:
                fecha_inicio_date = datetime.strptime(fecha_inicio, '%Y-%m-%d').date()
            except ValueError:
                fecha_inicio_date = None
        
        if fecha_fin:
            try:
                fecha_fin_date = datetime.strptime(fecha_fin, '%Y-%m-%d').date()
            except ValueError:
                fecha_fin_date = None
        
        try:
            cursor = mysql.connection.cursor()
            cursor.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")
            cursor.callproc('admin_facturas_lista', [fecha_inicio_date, fecha_fin_date, busqueda])
            facturas_raw = cursor.fetchall()
            while cursor.nextset():
                pass
            
            facturas = []
            for row in facturas_raw:
                factura_dict = {}
                for key, value in row.items():
                    if isinstance(value, bytes):
                        factura_dict[key] = value.decode('utf-8', errors='replace')
                    else:
                        factura_dict[key] = value
                facturas.append(factura_dict)
            
            cursor.close()
            return render_template(
                'facturas.html', 
                facturas=facturas,
                fecha_inicio=fecha_inicio or '',
                fecha_fin=fecha_fin or '',
                busqueda=busqueda or '',
                route_name='admin_facturas'
            )
        except Exception as e2:
            print(f"Error en fallback: {str(e2)}")
            return render_template(
                'facturas.html', 
                facturas=[],
                fecha_inicio=fecha_inicio or '',
                fecha_fin=fecha_fin or '',
                busqueda=busqueda or '',
                route_name='admin_facturas'
            )
    except Exception as e:
        import traceback
        error_msg = f"Error cargando facturas: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or ''
        fecha_fin = request.args.get('fecha_fin', '').strip() or ''
        busqueda = request.args.get('busqueda', '').strip() or ''
        
        return render_template(
            'facturas.html', 
            facturas=[],
            fecha_inicio=fecha_inicio,
            fecha_fin=fecha_fin,
            busqueda=busqueda,
            route_name='admin_facturas'
        )

@app.route('/admin/devoluciones')
@login_requerido
@requiere_rol('Admin')
def admin_devoluciones():
    """Gestión de devoluciones para admin"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener devoluciones con información completa usando SP
        cursor.callproc('sp_devoluciones_lista_admin', [])
        devoluciones = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('devoluciones.html', devoluciones=devoluciones)
    except Exception as e:
        import traceback
        print(f"Error cargando devoluciones admin: {str(e)}\n{traceback.format_exc()}")
        return render_template('devoluciones.html', devoluciones=[])

@app.route('/admin/empleados')
@login_requerido
@requiere_rol('Admin')
def admin_empleados():
    """Gestión de empleados para admin"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener todos los empleados usando SP
        cursor.callproc('sp_empleados_lista', [])
        empleados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        user = {
            "full_name": session.get("full_name", "Admin"),
            "role": session.get("role", "Admin")
        }
        
        return render_template('admin_empleados.html', empleados=empleados, user=user)
    except Exception as e:
        import traceback
        print(f"Error cargando empleados: {str(e)}\n{traceback.format_exc()}")
        return render_template('admin_empleados.html', empleados=[], user=user)

@app.route('/admin/empleados/crear')
@login_requerido
@requiere_rol('Admin')
def admin_empleados_crear():
    """Página para crear nuevo empleado"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener roles usando SP
        cursor.callproc('sp_roles_empleados', [])
        roles = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener sucursales activas usando SP
        cursor.callproc('sp_sucursales_activas', [])
        sucursales = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener géneros usando SP
        cursor.callproc('sp_generos_lista', [])
        generos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        user = {
            "full_name": session.get("full_name", "Admin"),
            "role": session.get("role", "Admin")
        }
        
        return render_template('admin_empleados_crear.html', roles=roles, sucursales=sucursales, generos=generos, user=user)
    except Exception as e:
        import traceback
        print(f"Error cargando datos para crear empleado: {str(e)}\n{traceback.format_exc()}")
        return render_template('error.html', mensaje='Error al cargar datos'), 500

@app.route('/api/admin/empleados/crear', methods=['POST'])
@login_requerido
@requiere_rol('Admin')
def api_admin_empleados_crear():
    """Endpoint para crear empleado y asociarlo a sucursal"""
    try:
        import MySQLdb.cursors
        from argon2 import PasswordHasher
        
        data = request.get_json()
        ph = PasswordHasher()
        
        # Validar datos requeridos
        nombre_usuario = data.get('nombre_usuario', '').strip()
        nombre_primero = data.get('nombre_primero', '').strip()
        apellido_paterno = data.get('apellido_paterno', '').strip()
        contrasena = data.get('contrasena', '').strip()
        id_rol = data.get('id_rol')
        id_sucursal = data.get('id_sucursal')
        
        if not nombre_usuario or not nombre_primero or not apellido_paterno or not contrasena:
            return jsonify({
                'success': False,
                'error': 'Nombre de usuario, nombre, apellido y contraseña son requeridos'
            }), 400
        
        if not id_rol or not id_sucursal:
            return jsonify({
                'success': False,
                'error': 'Rol y sucursal son requeridos'
            }), 400
        
        # Hash de la contraseña
        contrasena_hash = ph.hash(contrasena)
        
        # Obtener id_usuario_rol del admin actual
        user_id = session.get('user_id')
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        cursor.callproc('sp_usuario_rol_obtener', [user_id, 'Admin'])
        usuario_rol_result = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not usuario_rol_result:
            cursor.callproc('sp_usuario_rol_primero_activo', [user_id])
            usuario_rol_result = cursor.fetchone()
            while cursor.nextset():
                pass
        
        if not usuario_rol_result:
            cursor.close()
            return jsonify({
                'success': False,
                'error': 'No se encontró un rol de usuario válido'
            }), 400
        
        id_usuario_rol_admin = usuario_rol_result.get('id_usuario_rol', 0)
        
        # Llamar al stored procedure
        cursor.callproc('admin_empleado_crear', [
            nombre_usuario,
            nombre_primero,
            data.get('nombre_segundo', '').strip() or '',
            apellido_paterno,
            data.get('apellido_materno', '').strip() or '',
            data.get('rfc_usuario', '').strip() or '',
            data.get('telefono', '').strip() or '',
            data.get('correo', '').strip() or '',
            data.get('id_genero') or None,
            contrasena_hash,
            int(id_rol),
            int(id_sucursal),
            int(id_usuario_rol_admin)
        ])
        
        # Leer el resultado
        mensaje = None
        try:
            resultado = cursor.fetchone()
            if resultado:
                if isinstance(resultado, dict):
                    mensaje = resultado.get('Mensaje', '')
                elif isinstance(resultado, (list, tuple)) and len(resultado) > 0:
                    mensaje = resultado[0] if resultado[0] else ''
            
            while cursor.nextset():
                pass
        except Exception as e:
            import traceback
            traceback.print_exc()
        
        # Verificar si hubo error
        if mensaje and 'Error:' in mensaje:
            mysql.connection.rollback()
            cursor.close()
            return jsonify({
                'success': False,
                'error': mensaje.replace('Error: ', '').strip()
            }), 400
        
        mysql.connection.commit()
        cursor.close()
        
        return jsonify({
            'success': True,
            'mensaje': mensaje or 'Empleado registrado exitosamente'
        })
        
    except Exception as e:
        import traceback
        error_str = str(e)
        traceback.print_exc()
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        mensaje_error = 'Error al registrar el empleado'
        if 'Error:' in error_str:
            mensaje_error = error_str.split('Error:')[-1].strip()
        
        return jsonify({
            'success': False,
            'error': mensaje_error
        }), 500

@app.route('/admin/reportes')
@login_requerido
@requiere_rol('Admin')
def admin_reportes():
    """Reportes para admin"""
    return render_template('reportes.html')

# ==================== ENDPOINTS API PARA REPORTES AVANZADOS ====================

@app.route('/api/reporte/resumen-ejecutivo')
@login_requerido
@requiere_rol('Admin', 'Auditor')
def api_resumen_ejecutivo():
    """Endpoint para obtener resumen ejecutivo con KPIs - Todos los datos si no hay filtros"""
    try:
        from datetime import datetime, timedelta, date
        
        fecha_desde_str = request.args.get('desde')
        fecha_hasta_str = request.args.get('hasta')
        
        # Si no hay parámetros, usar todos los datos (fecha muy antigua)
        if not fecha_desde_str and not fecha_hasta_str:
            fecha_desde = date(2000, 1, 1)  # Fecha muy antigua para incluir todos
            fecha_hasta = datetime.now().date()
        else:
            fecha_hasta = datetime.now().date()
            if fecha_hasta_str:
                try:
                    fecha_hasta = datetime.strptime(fecha_hasta_str, '%Y-%m-%d').date()
                except:
                    pass
            
            if fecha_desde_str:
                try:
                    fecha_desde = datetime.strptime(fecha_desde_str, '%Y-%m-%d').date()
                except:
                    fecha_desde = date(2000, 1, 1)
            else:
                fecha_desde = date(2000, 1, 1)
        
        cursor = mysql.connection.cursor()
        
        # Ingresos totales
        cursor.callproc('admin_kpi_ventas_totales', [fecha_desde, fecha_hasta])
        ventas_result = cursor.fetchone()
        while cursor.nextset():
            pass
        ingresos_totales = float(ventas_result.get('total_ventas', 0) or 0) if ventas_result else 0
        
        # Total pedidos usando SP
        cursor.callproc('sp_pedidos_count_rango', [fecha_desde, fecha_hasta])
        pedidos_result = cursor.fetchone()
        while cursor.nextset():
            pass
        total_pedidos = int(pedidos_result.get('total_pedidos', 0) or 0) if pedidos_result else 0
        
        # Ticket promedio
        ticket_promedio = ingresos_totales / total_pedidos if total_pedidos > 0 else 0
        
        # Devoluciones usando SP
        cursor.callproc('sp_devoluciones_count_rango', [fecha_desde, fecha_hasta])
        devoluciones_result = cursor.fetchone()
        while cursor.nextset():
            pass
        total_devoluciones = int(devoluciones_result.get('total_devoluciones', 0) or 0) if devoluciones_result else 0
        
        # Tasa de devolución
        tasa_devolucion = (total_devoluciones / total_pedidos * 100) if total_pedidos > 0 else 0
        
        cursor.close()
        
        print(f"Resumen ejecutivo - Fechas: {fecha_desde} a {fecha_hasta}")
        print(f"Resumen ejecutivo - Ingresos: {ingresos_totales}, Pedidos: {total_pedidos}, Ticket: {ticket_promedio}")
        print(f"Resumen ejecutivo - Devoluciones: {total_devoluciones}, Tasa: {tasa_devolucion}%")
        
        return jsonify({
            'ingresos_totales': ingresos_totales,
            'total_pedidos': total_pedidos,
            'ticket_promedio': ticket_promedio,
            'total_devoluciones': total_devoluciones,
            'tasa_devolucion': tasa_devolucion
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_resumen_ejecutivo: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        # Devolver valores por defecto en caso de error
        return jsonify({
            'ingresos_totales': 0,
            'total_pedidos': 0,
            'ticket_promedio': 0,
            'total_devoluciones': 0,
            'tasa_devolucion': 0,
            'error': str(e)
        }), 200  # Devolver 200 para que el frontend pueda procesarlo

@app.route('/api/reporte/ventas-mes')
@login_requerido
@requiere_rol('Admin', 'Auditor')
def api_ventas_mes():
    """Endpoint para obtener ventas agrupadas por año - Últimos 5 años"""
    try:
        from datetime import datetime, timedelta, date
        
        cursor = mysql.connection.cursor()
        
        # Obtener ventas agrupadas por año usando SP
        cursor.callproc('sp_ventas_por_anio', [4])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Si no hay resultados, intentar con todos los años disponibles
        if not resultados or len(resultados) == 0:
            print("No se encontraron pedidos en los últimos 5 años, intentando con todos los años...")
            cursor.callproc('sp_ventas_por_anio_todos', [5])
            resultados = cursor.fetchall()
            while cursor.nextset():
                pass
            # Invertir para mostrar del más antiguo al más reciente
            resultados = list(reversed(resultados)) if resultados else []
        
        cursor.close()
        
        ventas_anio = []
        for row in resultados:
            anio = row.get('anio', '')
            if anio:
                ventas_anio.append({
                    'mes': str(anio),  # Usar 'mes' para mantener compatibilidad con el frontend
                    'anio': int(anio),
                    'total': float(row.get('total_anio', 0) or 0),
                    'facturas': int(row.get('pedidos_anio', 0) or 0)
                })
        
        print(f"Ventas por año - {len(ventas_anio)} años encontrados")
        if len(ventas_anio) > 0:
            print(f"Primer año: {ventas_anio[0]}")
            print(f"Último año: {ventas_anio[-1]}")
        else:
            print("ADVERTENCIA: No se encontraron datos de ventas por año")
        
        return jsonify(ventas_anio)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_ventas_mes: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        # Devolver array vacío en caso de error
        return jsonify([])

@app.route('/api/reporte/clientes-frecuentes')
@login_requerido
@requiere_rol('Admin', 'Auditor')
def api_clientes_frecuentes():
    """Endpoint para obtener clientes más frecuentes - Todos los datos si no hay filtros"""
    try:
        from datetime import datetime, timedelta, date
        
        fecha_desde_str = request.args.get('desde')
        fecha_hasta_str = request.args.get('hasta')
        limite = request.args.get('limite', 10, type=int)
        
        # Si no hay parámetros, usar todos los datos
        if not fecha_desde_str and not fecha_hasta_str:
            fecha_desde = date(2000, 1, 1)
            fecha_hasta = datetime.now().date()
        else:
            fecha_hasta = datetime.now().date()
            if fecha_hasta_str:
                try:
                    fecha_hasta = datetime.strptime(fecha_hasta_str, '%Y-%m-%d').date()
                except:
                    pass
            
            if fecha_desde_str:
                try:
                    fecha_desde = datetime.strptime(fecha_desde_str, '%Y-%m-%d').date()
                except:
                    fecha_desde = date(2000, 1, 1)
            else:
                fecha_desde = date(2000, 1, 1)
        
        cursor = mysql.connection.cursor()
        
        cursor.callproc('sp_top_clientes_pedidos', [fecha_desde, fecha_hasta])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        clientes = []
        for row in resultados:
            clientes.append({
                'nombre': row.get('nombre_completo', 'N/A'),
                'usuario': row.get('nombre_usuario', ''),
                'total_pedidos': int(row.get('total_pedidos', 0) or 0),
                'total_gastado': float(row.get('total_gastado', 0) or 0)
            })
        
        return jsonify(clientes)
    except Exception as e:
        import traceback
        print(f"Error en api_clientes_frecuentes: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/reporte/clientes-vip')
@login_requerido
@requiere_rol('Admin', 'Auditor')
def api_clientes_vip():
    """Endpoint para obtener clientes VIP (mayor gasto) - Todos los datos si no hay filtros"""
    try:
        from datetime import datetime, timedelta, date
        
        fecha_desde_str = request.args.get('desde')
        fecha_hasta_str = request.args.get('hasta')
        limite = request.args.get('limite', 10, type=int)
        
        # Si no hay parámetros, usar todos los datos
        if not fecha_desde_str and not fecha_hasta_str:
            fecha_desde = date(2000, 1, 1)
            fecha_hasta = datetime.now().date()
        else:
            fecha_hasta = datetime.now().date()
            if fecha_hasta_str:
                try:
                    fecha_hasta = datetime.strptime(fecha_hasta_str, '%Y-%m-%d').date()
                except:
                    pass
            
            if fecha_desde_str:
                try:
                    fecha_desde = datetime.strptime(fecha_desde_str, '%Y-%m-%d').date()
                except:
                    fecha_desde = date(2000, 1, 1)
            else:
                fecha_desde = date(2000, 1, 1)
        
        cursor = mysql.connection.cursor()
        
        cursor.callproc('sp_top_clientes_gasto', [fecha_desde, fecha_hasta, limite])
        
        resultados = cursor.fetchall()
        cursor.close()
        
        clientes = []
        for row in resultados:
            clientes.append({
                'nombre': row.get('nombre_completo', 'N/A'),
                'usuario': row.get('nombre_usuario', ''),
                'total_pedidos': int(row.get('total_pedidos', 0) or 0),
                'total_gastado': float(row.get('total_gastado', 0) or 0)
            })
        
        return jsonify(clientes)
    except Exception as e:
        import traceback
        print(f"Error en api_clientes_vip: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/reporte/devoluciones-analisis')
@login_requerido
@requiere_rol('Admin', 'Auditor')
def api_devoluciones_analisis():
    """Endpoint para análisis de devoluciones - Todos los datos si no hay filtros"""
    try:
        from datetime import datetime, timedelta, date
        
        fecha_desde_str = request.args.get('desde')
        fecha_hasta_str = request.args.get('hasta')
        
        # Si no hay parámetros, usar todos los datos
        if not fecha_desde_str and not fecha_hasta_str:
            fecha_desde = date(2000, 1, 1)
            fecha_hasta = datetime.now().date()
        else:
            fecha_hasta = datetime.now().date()
            if fecha_hasta_str:
                try:
                    fecha_hasta = datetime.strptime(fecha_hasta_str, '%Y-%m-%d').date()
                except:
                    pass
            
            if fecha_desde_str:
                try:
                    fecha_desde = datetime.strptime(fecha_desde_str, '%Y-%m-%d').date()
                except:
                    fecha_desde = date(2000, 1, 1)
            else:
                fecha_desde = date(2000, 1, 1)
        
        cursor = mysql.connection.cursor()
        
        # Devoluciones por año usando SP
        cursor.callproc('sp_devoluciones_por_anio', [4])
        devoluciones_anio = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Si no hay resultados, intentar con todos los años disponibles
        if not devoluciones_anio or len(devoluciones_anio) == 0:
            print("No se encontraron devoluciones en los últimos 5 años, intentando con todos los años...")
            cursor.callproc('sp_devoluciones_por_anio_todos', [5])
            devoluciones_anio = cursor.fetchall()
            while cursor.nextset():
                pass
            # Invertir para mostrar del más antiguo al más reciente
            devoluciones_anio = list(reversed(devoluciones_anio)) if devoluciones_anio else []
        
        # Lista de devoluciones recientes usando SP
        cursor.callproc('sp_devoluciones_recientes', [20])
        devoluciones_recientes = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        print(f"Devoluciones por año - {len(devoluciones_anio)} años encontrados")
        if len(devoluciones_anio) > 0:
            print(f"Primer año: {devoluciones_anio[0]}")
        
        print(f"Devoluciones recientes - {len(devoluciones_recientes)} encontradas")
        
        return jsonify({
            'devoluciones_anio': [{
                'anio': int(r.get('anio', 0) or 0),
                'cantidad': int(r.get('cantidad_devoluciones', 0) or 0),
                'productos': int(r.get('cantidad_productos', 0) or 0),
                'total': float(r.get('total_devolucion', 0) or 0)
            } for r in devoluciones_anio],
            'devoluciones': [{
                'id': int(r.get('id_devolucion', 0) or 0),
                'fecha': str(r.get('fecha_devolucion', '')),
                'estado': r.get('estado_devolucion', 'Pendiente'),
                'cantidad_productos': int(r.get('cantidad_productos', 0) or 0),
                'total': float(r.get('total_devolucion', 0) or 0)
            } for r in devoluciones_recientes]
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_devoluciones_analisis: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        # Devolver estructura vacía en caso de error
        return jsonify({
            'devoluciones_anio': [],
            'devoluciones': [],
            'error': str(e)
        }), 200  # Devolver 200 para que el frontend pueda procesarlo

@app.route('/api/reporte/inventario-bajo-stock')
@login_requerido
@requiere_rol('Admin', 'Auditor')
def api_inventario_bajo_stock():
    """Endpoint para obtener productos con bajo stock"""
    try:
        cursor = mysql.connection.cursor()
        
        # Intentar usar la view primero usando SP
        try:
            cursor.callproc('sp_inventario_bajo', [])
            resultados = cursor.fetchall()
            while cursor.nextset():
                pass
            if resultados and len(resultados) > 0:
                productos = []
                for row in resultados:
                    productos.append({
                        'nombre': row.get('nombre_producto', row.get('Nombre_Producto', 'N/A')),
                        'sku': row.get('sku', row.get('SKU', '')),
                        'stock_actual': int(row.get('stock_actual', row.get('Stock_Actual', 0)) or 0),
                        'stock_minimo': int(row.get('stock_minimo', row.get('Stock_Minimo', 0)) or 0)
                    })
                cursor.close()
                print(f"Inventario bajo stock - {len(productos)} productos encontrados (usando view)")
                return jsonify(productos)
        except Exception as view_error:
            print(f"View no disponible, usando consulta directa: {view_error}")
        
        # Si la view no funciona, usar SP de consulta directa
        cursor.callproc('sp_inventario_bajo_directo', [])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        productos = []
        for row in resultados:
            productos.append({
                'nombre': row.get('nombre_producto', 'N/A'),
                'sku': row.get('sku', ''),
                'stock_actual': int(row.get('stock_actual', 0) or 0),
                'stock_minimo': int(row.get('stock_minimo', 0) or 0)
            })
        
        print(f"Inventario bajo stock - {len(productos)} productos encontrados (usando consulta directa)")
        return jsonify(productos)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_inventario_bajo_stock: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify([])  # Devolver array vacío en caso de error

@app.route('/api/reporte/productos-rentables')
@login_requerido
@requiere_rol('Admin', 'Auditor')
def api_productos_rentables():
    """Endpoint para obtener productos más rentables - Todos los datos si no hay filtros"""
    try:
        from datetime import datetime, timedelta, date
        
        fecha_desde_str = request.args.get('desde')
        fecha_hasta_str = request.args.get('hasta')
        limite = request.args.get('limite', 10, type=int)
        
        # Si no hay parámetros, usar todos los datos
        if not fecha_desde_str and not fecha_hasta_str:
            fecha_desde = date(2000, 1, 1)
            fecha_hasta = datetime.now().date()
        else:
            fecha_hasta = datetime.now().date()
            if fecha_hasta_str:
                try:
                    fecha_hasta = datetime.strptime(fecha_hasta_str, '%Y-%m-%d').date()
                except:
                    pass
            
            if fecha_desde_str:
                try:
                    fecha_desde = datetime.strptime(fecha_desde_str, '%Y-%m-%d').date()
                except:
                    fecha_desde = date(2000, 1, 1)
            else:
                fecha_desde = date(2000, 1, 1)
        
        cursor = mysql.connection.cursor()
        
        cursor.callproc('sp_top_productos_vendidos', [fecha_desde, fecha_hasta, limite])
        
        resultados = cursor.fetchall()
        cursor.close()
        
        productos = []
        for row in resultados:
            productos.append({
                'nombre': row.get('nombre_producto', 'N/A'),
                'sku': row.get('sku', ''),
                'unidades_vendidas': int(row.get('unidades_vendidas', 0) or 0),
                'ingresos_totales': float(row.get('ingresos_totales', 0) or 0),
                'precio_promedio': float(row.get('precio_promedio', 0) or 0)
            })
        
        print(f"Productos rentables - {len(productos)} productos encontrados")
        return jsonify(productos)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_productos_rentables: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify([])  # Devolver array vacío en caso de error

@app.route('/admin/devoluciones/crear')
@login_requerido
@requiere_rol('Admin')
def admin_crear_devolucion():
    """Página para crear nueva devolución - admin"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener pedidos completados usando SP
        cursor.callproc('sp_pedidos_completados', [])
        pedidos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener tipos y motivos de devolución usando SP tiposMotivosDevolucion - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('tiposMotivosDevolucion', [])
        tipos_devolucion = cursor.fetchall()  # Primer result set: tipos de devolución
        cursor.nextset()  # Avanzar al segundo result set
        motivos_devolucion_raw = cursor.fetchall()  # Segundo result set: motivos de devolución
        # Consumir todos los resultados del SP
        while cursor.nextset():
            pass
        
        # Convertir motivos_devolucion de lista de diccionarios a lista de strings
        motivos_devolucion = [motivo['motivo_devolucion'] for motivo in motivos_devolucion_raw] if motivos_devolucion_raw else []
        
        cursor.close()
        
        print(f"Pedidos cargados: {len(pedidos)}, Tipos: {len(tipos_devolucion)}, Motivos: {len(motivos_devolucion)}")
        
        return render_template('admin_crear_devolucion.html', 
                            pedidos=pedidos, 
                            tipos_devolucion=tipos_devolucion,
                            motivos_devolucion=motivos_devolucion)
    except Exception as e:
        import traceback
        print(f"Error cargando página crear devolución admin: {str(e)}\n{traceback.format_exc()}")
        return render_template('admin_crear_devolucion.html', pedidos=[], tipos_devolucion=[], motivos_devolucion=[])

@app.route('/admin/catalogo')
@login_requerido
@requiere_rol('Admin')
def admin_catalogo():
    """Catálogo de productos para administración"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener todos los productos usando SP admin_inventario_productos - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('admin_inventario_productos', [])
        productos = cursor.fetchall()
        # Consumir todos los resultados del SP
        while cursor.nextset():
            pass
        
        cursor.close()
        
        return render_template('admin_catalogo.html', productos=productos)
    except Exception as e:
        import traceback
        print(f"Error cargando catálogo admin: {str(e)}\n{traceback.format_exc()}")
        return render_template('admin_catalogo.html', productos=[])

@app.route('/admin/inventario')
@login_requerido
@requiere_rol('Admin')
def admin_inventario():
    import MySQLdb.cursors

    # 1. Obtener inventario por producto (SP que ya tienes)
    cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur.callproc("admin_inventario_productos")
    productos = cur.fetchall()
    while cur.nextset():
        pass
    cur.close()

    # 2. Obtener sucursales para el filtro
    cur2 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur2.callproc('sp_sucursales_activas', [])
    sucursales = cur2.fetchall()
    while cur2.nextset():
        pass
    cur2.close()

    # 3. Obtener la sucursal del usuario actual (si tiene una asignada)
    sucursal_usuario = None
    id_usuario = session.get('user_id')
    if id_usuario:
        cur3 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cur3.callproc('sp_usuario_sucursal', [id_usuario])
        resultado_sucursal = cur3.fetchone()
        if resultado_sucursal:
            sucursal_usuario = resultado_sucursal['nombre_sucursal']
        cur3.close()
    
    # Si no tiene sucursal asignada, usar la primera sucursal activa
    if not sucursal_usuario and sucursales:
        sucursal_usuario = sucursales[0]['nombre_sucursal']

    # 4. Pasar también el usuario (si tu base.html lo usa)
    user = {
        "full_name": session.get("full_name", "Admin"),
        "role": session.get("role", "Admin")
    }

    return render_template(
        'admin_inventario.html',
        productos=productos,
        sucursales=sucursales,
        sucursal_usuario=sucursal_usuario,
        user=user
    )

@app.route('/admin/sucursales')
@login_requerido
@requiere_rol('Admin')
def admin_sucursales():
    """Gestión de sucursales y asignación de productos"""
    import MySQLdb.cursors
    
    # Obtener todas las sucursales ordenadas por ID con cantidad de usuarios usando SP
    cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur.callproc('admin_sucursales_lista')
    sucursales = cur.fetchall()
    while cur.nextset():
        pass
    cur.close()
    
    # Obtener todos los productos activos para asignación
    cur2 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur2.execute("""
        SELECT p.id_producto, m.nombre_producto, s.sku
        FROM Productos p
        JOIN Modelos m ON p.id_modelo = m.id_modelo
        JOIN Sku s ON p.id_sku = s.id_sku
        WHERE p.activo_producto = 1
        ORDER BY m.nombre_producto
    """)
    productos = cur2.fetchall()
    cur2.close()
    
    # Obtener todos los estados
    cur3 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur3.execute("""
        SELECT id_estado_direccion, estado_direccion
        FROM Estados_Direcciones
        ORDER BY estado_direccion
    """)
    estados = cur3.fetchall()
    cur3.close()
    
    user = {
        "full_name": session.get("full_name", "Admin"),
        "role": session.get("role", "Admin")
    }
    
    return render_template(
        'admin_sucursales.html',
        sucursales=sucursales,
        productos=productos,
        estados=estados,
        user=user
    )

@app.route('/admin/sucursales/crear')
@login_requerido
@requiere_rol('Admin')
def admin_sucursales_crear():
    """Página para crear una nueva sucursal"""
    import MySQLdb.cursors
    
    # Obtener todos los estados
    cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur.callproc('sp_estados_direcciones_lista', [])
    estados = cur.fetchall()
    while cur.nextset():
        pass
    cur.close()
    
    user = {
        "full_name": session.get("full_name", "Admin"),
        "role": session.get("role", "Admin")
    }
    
    return render_template(
        'admin_sucursales_crear.html',
        estados=estados,
        user=user
    )

@app.route('/admin/sucursales/asignar-producto')
@login_requerido
@requiere_rol('Admin')
def admin_sucursales_asignar_producto():
    """Página para asignar un producto a una sucursal"""
    import MySQLdb.cursors
    
    # Obtener todas las sucursales activas
    cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur.callproc('sp_sucursales_activas', [])
    sucursales = cur.fetchall()
    while cur.nextset():
        pass
    cur.close()
    
    # Obtener todos los productos activos usando SP
    cur2 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur2.callproc('sp_productos_para_sucursal', [])
    productos = cur2.fetchall()
    while cur2.nextset():
        pass
    cur2.close()
    
    user = {
        "full_name": session.get("full_name", "Admin"),
        "role": session.get("role", "Admin")
    }
    
    return render_template(
        'admin_sucursales_asignar_producto.html',
        sucursales=sucursales,
        productos=productos,
        user=user
    )

@app.route('/api/admin/sucursales/codigos-postales', methods=['GET'])
@login_requerido
@requiere_rol('Admin')
def api_codigos_postales_por_estado():
    """API para obtener códigos postales filtrados por estado"""
    try:
        id_estado = request.args.get('id_estado', type=int)
        
        if not id_estado:
            return jsonify({'success': False, 'error': 'ID de estado requerido'}), 400
        
        cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cur.callproc('sp_codigos_postales_por_estado', [id_estado])
        
        codigos_postales = cur.fetchall()
        cur.close()
        
        return jsonify({
            'success': True,
            'codigos_postales': codigos_postales
        })
    except Exception as e:
        import traceback
        error_msg = f"Error obteniendo códigos postales: {str(e)}\n{traceback.format_exc()}"
        print(error_msg, flush=True)
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/admin/sucursales/crear', methods=['POST'])
@login_requerido
@requiere_rol('Admin')
def api_crear_sucursal():
    """API para crear una nueva sucursal"""
    try:
        data = request.get_json()
        
        nombre_sucursal = data.get('nombre_sucursal', '').strip()
        calle_direccion = data.get('calle_direccion', '').strip()
        numero_direccion = data.get('numero_direccion', '').strip()
        codigo_postal = data.get('codigo_postal', '').strip()
        id_estado = data.get('id_estado')
        municipio = data.get('municipio', '').strip()
        activo_sucursal = data.get('activo_sucursal', True)
        
        # Validaciones básicas
        if not nombre_sucursal:
            return jsonify({'success': False, 'error': 'El nombre de la sucursal es requerido'}), 400
        if not calle_direccion:
            return jsonify({'success': False, 'error': 'La calle es requerida'}), 400
        if not numero_direccion:
            return jsonify({'success': False, 'error': 'El número de dirección es requerido'}), 400
        if not codigo_postal:
            return jsonify({'success': False, 'error': 'El código postal es requerido'}), 400
        
        # Convertir id_estado a int si existe
        if id_estado:
            try:
                id_estado = int(id_estado)
            except (ValueError, TypeError):
                id_estado = None
        else:
            id_estado = None
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sucursalCrear', [
            nombre_sucursal,
            calle_direccion,
            numero_direccion,
            codigo_postal,
            id_estado,
            municipio if municipio else None,
            activo_sucursal
        ])
        
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        
        mysql.connection.commit()
        cursor.close()
        
        if resultado:
            return jsonify({
                'success': True,
                'mensaje': 'Sucursal creada exitosamente',
                'id_sucursal': resultado.get('id_sucursal_creada')
            })
        else:
            return jsonify({'success': False, 'error': 'No se pudo crear la sucursal'}), 500
            
    except Exception as e:
        import traceback
        error_msg = f"Error creando sucursal: {str(e)}\n{traceback.format_exc()}"
        print(error_msg, flush=True)
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        error_str = str(e)
        mensaje_usuario = 'Error al crear la sucursal.'
        
        if 'Error:' in error_str:
            parts = error_str.split('Error:', 1)
            if len(parts) > 1:
                mensaje_usuario = parts[1].strip()
        elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
            if ':' in error_str:
                mensaje_usuario = error_str.split(':', 1)[-1].strip()
        elif 'Duplicate entry' in error_str:
            mensaje_usuario = 'Ya existe una sucursal con ese nombre.'
        
        return jsonify({
            'success': False,
            'error': str(e),
            'mensaje': mensaje_usuario
        }), 500

@app.route('/api/admin/sucursales/cambiar-estado', methods=['POST'])
@login_requerido
@requiere_rol('Admin')
def api_cambiar_estado_sucursal():
    """API para activar/desactivar una sucursal"""
    try:
        data = request.get_json()
        
        id_sucursal = data.get('id_sucursal')
        activo_sucursal = data.get('activo_sucursal', True)
        
        if not id_sucursal:
            return jsonify({'success': False, 'error': 'ID de sucursal requerido'}), 400
        
        try:
            id_sucursal = int(id_sucursal)
        except (ValueError, TypeError):
            return jsonify({'success': False, 'error': 'ID de sucursal inválido'}), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sp_sucursal_actualizar_estado', [id_sucursal, activo_sucursal])
        while cursor.nextset():
            pass
        mysql.connection.commit()
        cursor.close()
        
        accion = 'activada' if activo_sucursal else 'desactivada'
        return jsonify({
            'success': True,
            'mensaje': f'Sucursal {accion} exitosamente'
        })
        
    except Exception as e:
        import traceback
        error_msg = f"Error cambiando estado de sucursal: {str(e)}\n{traceback.format_exc()}"
        print(error_msg, flush=True)
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        return jsonify({
            'success': False,
            'error': str(e),
            'mensaje': 'Error al cambiar el estado de la sucursal'
        }), 500

@app.route('/api/admin/sucursales/actualizar', methods=['POST'])
@login_requerido
@requiere_rol('Admin')
def api_actualizar_sucursal():
    """API para actualizar una sucursal"""
    try:
        data = request.get_json()
        
        id_sucursal = data.get('id_sucursal')
        nombre_sucursal = data.get('nombre_sucursal', '').strip()
        calle_direccion = data.get('calle_direccion', '').strip()
        numero_direccion = data.get('numero_direccion', '').strip()
        codigo_postal = data.get('codigo_postal', '').strip()
        id_estado = data.get('id_estado')
        municipio = data.get('municipio', '').strip()
        activo_sucursal = data.get('activo_sucursal', True)
        
        # Validaciones básicas
        if not id_sucursal:
            return jsonify({'success': False, 'error': 'ID de sucursal requerido'}), 400
        if not nombre_sucursal:
            return jsonify({'success': False, 'error': 'El nombre de la sucursal es requerido'}), 400
        if not calle_direccion:
            return jsonify({'success': False, 'error': 'La calle es requerida'}), 400
        if not numero_direccion:
            return jsonify({'success': False, 'error': 'El número de dirección es requerido'}), 400
        if not codigo_postal:
            return jsonify({'success': False, 'error': 'El código postal es requerido'}), 400
        
        # Convertir id_estado a int si existe
        if id_estado:
            try:
                id_estado = int(id_estado)
            except (ValueError, TypeError):
                id_estado = None
        else:
            id_estado = None
        
        try:
            id_sucursal = int(id_sucursal)
        except (ValueError, TypeError):
            return jsonify({'success': False, 'error': 'ID de sucursal inválido'}), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sucursalActualizar', [
            id_sucursal,
            nombre_sucursal,
            calle_direccion,
            numero_direccion,
            codigo_postal,
            id_estado,
            municipio if municipio else None,
            activo_sucursal
        ])
        
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        
        mysql.connection.commit()
        cursor.close()
        
        if resultado:
            return jsonify({
                'success': True,
                'mensaje': resultado.get('Mensaje', 'Sucursal actualizada exitosamente')
            })
        else:
            return jsonify({'success': False, 'error': 'No se pudo actualizar la sucursal'}), 500
            
    except Exception as e:
        import traceback
        error_msg = f"Error actualizando sucursal: {str(e)}\n{traceback.format_exc()}"
        print(error_msg, flush=True)
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        error_str = str(e)
        mensaje_usuario = 'Error al actualizar la sucursal.'
        
        if 'Error:' in error_str:
            parts = error_str.split('Error:', 1)
            if len(parts) > 1:
                mensaje_usuario = parts[1].strip()
        elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
            if ':' in error_str:
                mensaje_usuario = error_str.split(':', 1)[-1].strip()
        elif 'Duplicate entry' in error_str:
            mensaje_usuario = 'Ya existe otra sucursal con ese nombre.'
        
        return jsonify({
            'success': False,
            'error': str(e),
            'mensaje': mensaje_usuario
        }), 500

@app.route('/api/admin/sucursales/producto/asignar', methods=['POST'])
@login_requerido
@requiere_rol('Admin')
def api_asignar_producto_sucursal():
    """API para asignar un producto a una sucursal con stocks"""
    try:
        data = request.get_json()
        
        id_sucursal = data.get('id_sucursal')
        id_producto = data.get('id_producto')
        stock_ideal = data.get('stock_ideal', 0)
        stock_actual = data.get('stock_actual', 0)
        stock_maximo = data.get('stock_maximo', 0)
        
        # Validaciones básicas
        if not id_sucursal:
            return jsonify({'success': False, 'error': 'La sucursal es requerida'}), 400
        if not id_producto:
            return jsonify({'success': False, 'error': 'El producto es requerido'}), 400
        
        # Convertir a enteros
        try:
            id_sucursal = int(id_sucursal)
            id_producto = int(id_producto)
            stock_ideal = int(stock_ideal)
            stock_actual = int(stock_actual)
            stock_maximo = int(stock_maximo)
        except (ValueError, TypeError):
            return jsonify({'success': False, 'error': 'Los valores deben ser números enteros'}), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sucursalProductoAsignar', [
            id_sucursal,
            id_producto,
            stock_ideal,
            stock_actual,
            stock_maximo
        ])
        
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        
        mysql.connection.commit()
        cursor.close()
        
        if resultado:
            return jsonify({
                'success': True,
                'mensaje': resultado.get('Mensaje', 'Producto asignado exitosamente')
            })
        else:
            return jsonify({'success': False, 'error': 'No se pudo asignar el producto'}), 500
            
    except Exception as e:
        import traceback
        error_msg = f"Error asignando producto a sucursal: {str(e)}\n{traceback.format_exc()}"
        print(error_msg, flush=True)
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        error_str = str(e)
        mensaje_usuario = 'Error al asignar el producto a la sucursal.'
        
        if 'Error:' in error_str:
            parts = error_str.split('Error:', 1)
            if len(parts) > 1:
                mensaje_usuario = parts[1].strip()
        elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
            if ':' in error_str:
                mensaje_usuario = error_str.split(':', 1)[-1].strip()
        
        return jsonify({
            'success': False,
            'error': str(e),
            'mensaje': mensaje_usuario
        }), 500

@app.route('/ventas')
@login_requerido
@requiere_rol('Vendedor')
def ventas():
    """Panel de ventas - solo para rol Vendedor"""
    return render_template('ventas_dashboard.html')

@app.route('/ventas/pedidos')
@login_requerido
@requiere_rol('Vendedor', 'Admin')
def ventas_pedidos():
    """Página de gestión de pedidos para ventas"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener pedidos usando SP ventas_pedidos_lista - SOLO SP, NO SQL EMBEBIDO
        # Parámetros: p_fecha_filtro (NULL = sin filtro), p_orden_fecha ('DESC' para más recientes primero)
        cursor.callproc('ventas_pedidos_lista', [None, 'DESC'])
        pedidos = cursor.fetchall()
        # Consumir todos los resultados del SP
        while cursor.nextset():
            pass
        
        # Obtener estados disponibles usando SP ventas_estados_pedidos - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('ventas_estados_pedidos', [])
        estados_disponibles = cursor.fetchall()
        # Consumir todos los resultados del SP
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('ventas_pedidos.html', pedidos=pedidos, estados_disponibles=estados_disponibles)
    except Exception as e:
        import traceback
        print(f"Error cargando pedidos: {str(e)}\n{traceback.format_exc()}")
        return render_template('ventas_pedidos.html', pedidos=[], estados_disponibles=[])

@app.route('/ventas/facturas')
@login_requerido
@requiere_rol('Vendedor')
def ventas_facturas():
    """Gestión de facturas para ventas"""
    try:
        # Obtener parámetros de filtro de la URL
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or None
        fecha_fin = request.args.get('fecha_fin', '').strip() or None
        busqueda = request.args.get('busqueda', '').strip() or None
        
                # Convertir fechas de string a date si están presentes
        fecha_inicio_date = None
        fecha_fin_date = None

        if fecha_inicio:
            try:
                fecha_inicio_date = datetime.strptime(fecha_inicio, '%Y-%m-%d').date()
            except ValueError:
                fecha_inicio_date = None

        if fecha_fin:
            try:
                fecha_fin_date = datetime.strptime(fecha_fin, '%Y-%m-%d').date()
            except ValueError:
                fecha_fin_date = None

        # Asegurar que la conexión siga viva
        try:
            mysql.connection.ping(reconnect=True)
        except:
            pass

        # Crear cursor para el stored procedure
        cursor = mysql.connection.cursor()
        cursor.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")

        facturas = []

        try:
            # Limpiar result sets previos por si acaso
            while cursor.nextset():
                pass

            # Llamar SOLO al SP, nada de SQL embebido
            cursor.callproc('admin_facturas_lista', [fecha_inicio_date, fecha_fin_date, busqueda])
            facturas_raw = cursor.fetchall()

            # Consumir result sets extra
            while cursor.nextset():
                pass

            # Convertir y decodificar cada fila
            for row in facturas_raw:
                try:
                    decoded_row = decode_row(row)
                    if not decoded_row:
                        continue

                    # Normalizar fecha_emision si viene como string
                    if 'fecha_emision' in decoded_row and decoded_row['fecha_emision']:
                        if isinstance(decoded_row['fecha_emision'], str):
                            parsed = None
                            for fmt in ('%Y-%m-%d', '%Y-%m-%d %H:%M:%S'):
                                try:
                                    parsed = datetime.strptime(decoded_row['fecha_emision'], fmt).date()
                                    break
                                except ValueError:
                                    continue
                            if parsed:
                                decoded_row['fecha_emision'] = parsed

                    facturas.append(decoded_row)

                except Exception as decode_error:
                    import traceback
                    print("[ERROR] Error decodificando fila:", decode_error)
                    traceback.print_exc()
                    # seguimos con la siguiente fila
                    continue

        except Exception as sp_error:
            import traceback
            error_msg = f"[ERROR] Error ejecutando stored procedure: {sp_error}\n{traceback.format_exc()}"
            print(error_msg)
            facturas = []
        finally:
            cursor.close()

        return render_template(
            'ventas_facturas.html',
            facturas=facturas,
            fecha_inicio=fecha_inicio or '',
            fecha_fin=fecha_fin or '',
            busqueda=busqueda or ''
        )

    except Exception as e:
        import traceback
        error_msg = f"Error cargando facturas: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Obtener parámetros para mantener los filtros en caso de error
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or ''
        fecha_fin = request.args.get('fecha_fin', '').strip() or ''
        busqueda = request.args.get('busqueda', '').strip() or ''
        
        return render_template('ventas_facturas.html', 
                            facturas=[],
                            fecha_inicio=fecha_inicio,
                            fecha_fin=fecha_fin,
                            busqueda=busqueda)

@app.route('/api/ventas/pagos/metodos')
def api_metodos_pago():
    """Endpoint para obtener métodos de pago"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('sp_metodos_pago_lista', [])
        metodos = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        return jsonify(metodos)
    except Exception as e:
        import traceback
        print(f"Error obteniendo métodos de pago: {str(e)}\n{traceback.format_exc()}")
        return jsonify([]), 500

@app.route('/api/ventas/facturas/<int:id_factura>/total')
def api_factura_total(id_factura):
    """Endpoint para obtener el total de una factura"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('sp_factura_total', [id_factura])
        factura = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()
        
        if factura:
            return jsonify({'total': float(factura.get('total', 0))})
        else:
            return jsonify({'error': 'Factura no encontrada'}), 404
    except Exception as e:
        import traceback
        print(f"Error obteniendo total de factura: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/ventas/pagos')
@login_requerido
@requiere_rol('Vendedor')
def ventas_pagos():
    """Página de gestión de pagos para ventas"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener facturas pendientes usando SP
        cursor.callproc('sp_facturas_pendientes', [])
        facturas_pendientes = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener métodos de pago
        cursor.callproc('sp_metodos_pago_lista', [])
        metodos_pago = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        return render_template('ventas_pagos.html', 
                            facturas_pendientes=facturas_pendientes,
                            metodos_pago=metodos_pago)
    except Exception as e:
        import traceback
        print(f"Error cargando página de pagos: {str(e)}\n{traceback.format_exc()}")
        return render_template('ventas_pagos.html', facturas_pendientes=[], metodos_pago=[])

@app.route('/api/ventas/pagos/registrar', methods=['POST'])
def api_registrar_pago():
    """Endpoint para registrar pago usando SOLO SP pagoRegistrar - SIN SQL EMBEBIDO"""
    try:
        data = request.get_json()
        
        # Extraer y validar datos requeridos
        id_factura = data.get('id_factura')
        importe = data.get('importe')
        id_metodo_pago = data.get('id_metodo_pago')
        
        # Validaciones básicas
        if not id_factura:
            return jsonify({'error': 'El ID de factura es requerido'}), 400
        if not importe or importe <= 0:
            return jsonify({'error': 'El importe debe ser mayor a 0'}), 400
        if not id_metodo_pago:
            return jsonify({'error': 'El método de pago es requerido'}), 400
        
        cursor = mysql.connection.cursor()
        
        # Llamar al SP pagoRegistrar - SOLO SP, NO SQL EMBEBIDO
        # Parámetros: var_id_factura, var_importe, var_id_metodo_pago
        cursor.callproc('pagoRegistrar', [
            int(id_factura),
            float(importe),
            int(id_metodo_pago)
        ])
        
        # El SP retorna un SELECT con el mensaje
        resultado = cursor.fetchone()
        mensaje = 'Pago registrado exitosamente'
        
        if resultado:
            # El SP retorna: SELECT CONCAT('Pago registrado. Nuevo estado: ', var_nuevo_estado) AS Mensaje
            if isinstance(resultado, dict):
                mensaje = resultado.get('Mensaje', mensaje)
            else:
                mensaje = resultado[0] if resultado else mensaje
        
        # Asegurar que el commit se refleje
        mysql.connection.commit()
        cursor.close()
        
        return jsonify({
            'success': True,
            'mensaje': mensaje
        })
    except Exception as e:
        import traceback
        error_msg = f"Error registrando pago: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Intentar extraer mensaje de error del SP si es posible
        mensaje_error = str(e)
        if 'Error:' in mensaje_error:
            mensaje_error = mensaje_error.split('Error:')[-1].strip()
        
        return jsonify({
            'error': mensaje_error,
            'mensaje': 'Error al registrar el pago. Verifique que la factura exista y que el importe sea válido.'
        }), 500

@app.route('/api/ventas/pedidos/<int:id_pedido>/pagar', methods=['POST'])
def api_pagar_pedido(id_pedido):
    """Endpoint para registrar pago inmediato después de crear pedido usando SOLO SP pagoRegistrar"""
    try:
        data = request.get_json()
        
        # Extraer y validar datos requeridos
        importe = data.get('importe')
        id_metodo_pago = data.get('id_metodo_pago')
        
        # Validaciones básicas
        if not importe or importe <= 0:
            return jsonify({'error': 'El importe debe ser mayor a 0'}), 400
        if not id_metodo_pago:
            return jsonify({'error': 'El método de pago es requerido'}), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener la factura asociada al pedido
        cursor.callproc('sp_factura_por_pedido', [id_pedido])
        factura = cursor.fetchone()
        while cursor.nextset():
            pass
        
        # Si no hay factura, usar el stored procedure para pagos sin factura
        if not factura:
            # Llamar al SP pagoRegistrarPedido - permite pagar sin factura
            try:
                cursor.callproc('pagoRegistrarPedido', [
                    int(id_pedido),
                    float(importe),
                    int(id_metodo_pago)
                ])
                
                # El SP retorna un SELECT con el mensaje
                resultado = cursor.fetchone()
                
                # Consumir todos los result sets
                while cursor.nextset():
                    pass
                
                mensaje = 'Pago registrado exitosamente'
                
                if resultado:
                    if isinstance(resultado, dict):
                        mensaje = resultado.get('Mensaje', mensaje)
                    else:
                        mensaje = resultado[0] if resultado else mensaje
                
                # Asegurar que el commit se refleje
                mysql.connection.commit()
                cursor.close()
                
                return jsonify({
                    'success': True,
                    'mensaje': mensaje,
                    'id_factura': None  # No hay factura
                })
            except Exception as pago_error:
                cursor.close()
                mysql.connection.rollback()
                error_msg = str(pago_error)
                return jsonify({
                    'success': False,
                    'error': error_msg,
                    'mensaje': f'Error al registrar el pago: {error_msg}'
                }), 500
        
        # Si hay factura, usar el stored procedure pagoRegistrar
        id_factura = factura.get('id_factura')
        
        if not id_factura:
            cursor.close()
            return jsonify({
                'success': False,
                'error': 'No se pudo obtener el ID de la factura.',
                'mensaje': 'No se pudo obtener el ID de la factura.'
            }), 500
        
        # Llamar al SP pagoRegistrar - SOLO SP, NO SQL EMBEBIDO
        try:
            cursor.callproc('pagoRegistrar', [
                int(id_factura),
                float(importe),
                int(id_metodo_pago)
            ])
            
            # El SP retorna un SELECT con el mensaje
            resultado = cursor.fetchone()
            
            # Consumir todos los result sets
            while cursor.nextset():
                pass
            
            mensaje = 'Pago registrado exitosamente'
            
            if resultado:
                if isinstance(resultado, dict):
                    mensaje = resultado.get('Mensaje', mensaje)
                else:
                    mensaje = resultado[0] if resultado else mensaje
            
            # Asegurar que el commit se refleje
            mysql.connection.commit()
            cursor.close()
            
            return jsonify({
                'success': True,
                'mensaje': mensaje,
                'id_factura': id_factura
            })
        except Exception as pago_error:
            # Error al registrar el pago
            cursor.close()
            mysql.connection.rollback()
            
            error_msg = str(pago_error)
            import traceback
            print(f"Error en pagoRegistrar: {error_msg}\n{traceback.format_exc()}")
            
            # Extraer mensaje del error
            if 'Error:' in error_msg:
                mensaje_error = error_msg.split('Error:')[-1].strip()
            elif 'La factura no existe' in error_msg:
                mensaje_error = 'La factura no existe. Por favor, contacte al soporte.'
            elif 'no puede ser mayor al pendiente' in error_msg:
                mensaje_error = error_msg
            elif 'debe ser mayor a cero' in error_msg:
                mensaje_error = 'El importe debe ser mayor a cero.'
            else:
                mensaje_error = error_msg
            
            return jsonify({
                'success': False,
                'error': mensaje_error,
                'mensaje': f'Error al registrar el pago: {mensaje_error}'
            }), 500
    except Exception as e:
        import traceback
        error_msg = f"Error registrando pago del pedido: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Asegurar rollback en caso de error
        try:
            if 'cursor' in locals():
                cursor.close()
            mysql.connection.rollback()
        except:
            pass
        
        mensaje_error = str(e)
        if 'Error:' in mensaje_error:
            mensaje_error = mensaje_error.split('Error:')[-1].strip()
        
        return jsonify({
            'success': False,
            'error': mensaje_error,
            'mensaje': f'Error al registrar el pago: {mensaje_error}'
        }), 500

@app.route('/ventas/catalogo')
@login_requerido
@requiere_rol('Vendedor')
def ventas_catalogo():
    """Catálogo de productos para ventas"""
    categoria_seleccionada = request.args.get('categoria', '')
    
    try:
        # Cursor normal para stored procedures
        cursor_cat = mysql.connection.cursor()
        
        # Obtener categorías activas usando SP categoriasActivas - SOLO SP, NO SQL EMBEBIDO
        cursor_cat.callproc('categoriasActivas', [])
        categorias = cursor_cat.fetchall()
        while cursor_cat.nextset():
            pass
        cursor_cat.close()
        
        # Cursor con DictCursor para consultas SQL directas (permite acceso por nombre)
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener productos con información completa para ventas usando SP
        categoria_param = categoria_seleccionada if categoria_seleccionada else None
        cursor.callproc('sp_productos_catalogo_ventas', [categoria_param])
        productos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
    except Exception as e:
        import traceback
        print(f"Error cargando catálogo ventas: {str(e)}\n{traceback.format_exc()}")
        productos = []
        categorias = []
    
    return render_template('ventas_catalogo.html', productos=productos, categorias=categorias, categoria_seleccionada=categoria_seleccionada)

@app.route('/ventas/devoluciones')
@login_requerido
@requiere_rol('Vendedor')
def ventas_devoluciones():
    """Página de gestión de devoluciones para ventas"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener devoluciones con información completa usando SP
        cursor.callproc('sp_devoluciones_lista_ventas', [])
        devoluciones = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('ventas_devoluciones.html', devoluciones=devoluciones)
    except Exception as e:
        import traceback
        print(f"Error cargando devoluciones ventas: {str(e)}\n{traceback.format_exc()}")
        return render_template('ventas_devoluciones.html', devoluciones=[])

@app.route('/ventas/reportes')
@login_requerido
@requiere_rol('Vendedor')
def ventas_reportes():
    """Página de reportes para ventas"""
    return render_template('ventas_reportes.html')

@app.route('/ventas/devoluciones/crear')
@login_requerido
@requiere_rol('Vendedor')
def ventas_crear_devolucion():
    """Página para crear nueva devolución"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener pedidos con detalles para devolución usando SP
        cursor.callproc('sp_pedidos_para_devolucion', [])
        pedidos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener tipos y motivos de devolución usando SP tiposMotivosDevolucion - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('tiposMotivosDevolucion', [])
        tipos_devolucion = cursor.fetchall()  # Primer result set: tipos de devolución
        cursor.nextset()  # Avanzar al segundo result set
        motivos_devolucion_raw = cursor.fetchall()  # Segundo result set: motivos de devolución
        # Consumir todos los resultados del SP
        while cursor.nextset():
            pass
        
        # Convertir motivos_devolucion de lista de diccionarios a lista de strings
        motivos_devolucion = [motivo['motivo_devolucion'] for motivo in motivos_devolucion_raw] if motivos_devolucion_raw else []
        
        cursor.close()
        
        return render_template('ventas_crear_devolucion.html', 
                            pedidos=pedidos, 
                            tipos_devolucion=tipos_devolucion,
                            motivos_devolucion=motivos_devolucion)
    except Exception as e:
        import traceback
        print(f"Error cargando página crear devolución: {str(e)}\n{traceback.format_exc()}")
        return render_template('ventas_crear_devolucion.html', pedidos=[], tipos_devolucion=[], motivos_devolucion=[])

@app.route('/api/ventas/devoluciones/pedido/<int:id_pedido>/productos')
def api_obtener_productos_pedido(id_pedido):
    """Obtener productos de un pedido para devolución"""
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("""
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
            WHERE pd.id_pedido = %s
        """, (id_pedido,))
        productos = cursor.fetchall()
        cursor.close()
        
        return jsonify(productos)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/ventas/devoluciones/crear', methods=['POST'])
def api_crear_devolucion():
    """Endpoint para crear devolución usando SP devolucionCrear"""
    try:
        data = request.get_json()
        id_pedido = data.get('id_pedido')
        items = data.get('items', [])
        
        if not id_pedido:
            return jsonify({'error': 'ID de pedido requerido'}), 400
        
        if not items or len(items) == 0:
            return jsonify({'error': 'Debe seleccionar al menos un producto para devolver'}), 400
        
        # Preparar JSON para el SP (formato esperado por devolucionCrear)
        # El SP espera: id_producto (INT), cantidad (INT), motivo (VARCHAR), id_tipo_devolucion (INT)
        items_json = []
        for item in items:
            # Asegurar que los valores sean del tipo correcto (enteros para id_producto, cantidad, id_tipo_devolucion)
            id_producto = int(item.get('id_producto', 0))
            cantidad = int(item.get('cantidad', 1))
            motivo = str(item.get('motivo', '')).strip()
            id_tipo_devolucion = int(item.get('id_tipo_devolucion', 1))
            
            if id_producto <= 0:
                return jsonify({'error': 'ID de producto inválido'}), 400
            if cantidad <= 0:
                return jsonify({'error': 'La cantidad debe ser mayor a 0'}), 400
            
            items_json.append({
                'id_producto': id_producto,
                'cantidad': cantidad,
                'motivo': motivo,
                'id_tipo_devolucion': id_tipo_devolucion
            })
        
        import json
        items_json_str = json.dumps(items_json, ensure_ascii=False)
        
        cursor = mysql.connection.cursor()
        
        # Llamar al SP devolucionCrear
        # Parámetros: p_id_pedido (INT), p_items_json (TEXT)
        # El SP retorna: SELECT v_id_devolucion AS id_devolucion_generada
        cursor.callproc('devolucionCrear', [int(id_pedido), items_json_str])
        
        # Leer el resultado del SP (el SELECT que retorna)
        id_devolucion = None
        
        # Obtener el resultado del SELECT que retorna el SP
        try:
            resultado = cursor.fetchone()
            if resultado:
                id_devolucion = resultado.get('id_devolucion_generada', 0) if isinstance(resultado, dict) else resultado[0]
                print(f"Devolución creada con ID: {id_devolucion}")
            
            # Consumir todos los result sets restantes para evitar "Commands out of sync"
            while cursor.nextset():
                pass
        except Exception as e:
            print(f"Error leyendo resultado del SP: {e}")
        
        # Cerrar cursor antes de abrir otro
        cursor.close()
        
        # Si no se pudo obtener del resultado, obtener el último ID insertado
        if not id_devolucion or id_devolucion == 0:
            print("No se pudo obtener ID del SP, consultando MAX(id_devolucion)...")
            cursor2 = mysql.connection.cursor()
            cursor2.callproc('sp_devolucion_max_id', [])
            resultado_max = cursor2.fetchone()
            while cursor2.nextset():
                pass
            id_devolucion = resultado_max.get('id_devolucion', 0) if resultado_max else 0
            cursor2.close()
            print(f"ID obtenido de MAX: {id_devolucion}")
        
        return jsonify({
            'success': True,
            'mensaje': 'Devolución creada exitosamente',
            'id_devolucion': id_devolucion
        })
    except Exception as e:
        import traceback
        error_msg = f"Error creando devolución: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Extraer mensaje de error del trigger/SP si es posible
        error_str = str(e)
        mensaje_usuario = 'Error al crear la devolución.'
        tipo_error = 'error'  # 'error', 'warning', 'info'
        
        # Si el error contiene un mensaje del trigger/SP (error 1644 es SIGNAL de MySQL)
        if '1644' in error_str or 'SIGNAL' in error_str or 'OperationalError' in error_str:
            # Intentar extraer el mensaje personalizado del trigger/SP
            import re
            
            # Buscar el mensaje entre comillas dobles o simples
            match = re.search(r'["\']([^"\']+)["\']', error_str)
            if match:
                mensaje_extraido = match.group(1)
                mensaje_usuario = mensaje_extraido
                
                # Identificar tipo de error según el mensaje
                if '30 días' in mensaje_extraido or '30 dias' in mensaje_extraido:
                    tipo_error = 'warning'
                    mensaje_usuario = 'No es posible devolver el producto después de 30 días de la fecha del pedido.'
                elif 'no pertenece' in mensaje_extraido.lower():
                    tipo_error = 'error'
                elif 'cantidad' in mensaje_extraido.lower() and 'mayor' in mensaje_extraido.lower():
                    tipo_error = 'error'
                elif 'completado' in mensaje_extraido.lower():
                    tipo_error = 'warning'
                elif 'fecha' in mensaje_extraido.lower() and 'inválida' in mensaje_extraido.lower():
                    tipo_error = 'error'
            else:
                # Fallback: buscar mensajes conocidos
                if 'No es posible devolver' in error_str or '30' in error_str:
                    mensaje_usuario = 'No es posible devolver el producto después de 30 días de la fecha del pedido.'
                    tipo_error = 'warning'
                elif 'no pertenece al pedido' in error_str.lower():
                    mensaje_usuario = 'Uno de los productos seleccionados no pertenece al pedido indicado.'
                elif 'cantidad mayor' in error_str.lower():
                    mensaje_usuario = 'No se puede devolver una cantidad mayor a la comprada.'
                elif 'completado' in error_str.lower():
                    mensaje_usuario = 'El pedido debe estar completado para poder procesar la devolución.'
                    tipo_error = 'warning'
        
        mysql.connection.rollback()  # Rollback en caso de error
        
        return jsonify({
            'error': error_str,
            'mensaje': mensaje_usuario,
            'tipo_error': tipo_error,
            'success': False
        }), 500

@app.route('/inventario') 
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def inventario(): 
    """Panel de inventario - solo para rol Inventarios o Gestor de Sucursal"""
    return render_template('inventario_dashboard.html')

@app.route('/ventas/pedidos/crear')
@login_requerido
@requiere_rol('Vendedor', 'Admin')
def ventas_crear_pedido():
    """Página para crear nuevo pedido - Vendedor y Admin"""
    productos = []
    clientes = []
    
    try:
        cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)

        # Productos activos usando SP
        cur.callproc('sp_productos_activos_pedido', [])
        productos = cur.fetchall()
        while cur.nextset():
            pass
        print(f"Productos cargados: {len(productos)}")

        # Lista de clientes SOLO para Admin / Vendedor
        rol = (session.get("role") or "").lower()
        if rol in ("admin", "vendedor"):
            cur.execute("""
                SELECT 
                    cl.id_cliente,
                    CONCAT(
                        u.nombre_primero, ' ',
                        IFNULL(u.nombre_segundo, ''), ' ',
                        u.apellido_paterno, ' ',
                        IFNULL(u.apellido_materno, '')
                    ) AS nombre_completo,
                    u.correo
                FROM Clientes cl
                JOIN Usuarios u ON cl.id_usuario = u.id_usuario
                ORDER BY nombre_completo
            """)
            clientes = cur.fetchall()
            print(f"Clientes cargados: {len(clientes)}")

        cur.close()

    except Exception as e:
        import traceback
        print(f"Error cargando página crear pedido: {e}\n{traceback.format_exc()}")

    return render_template(
        'ventas_crear_pedido.html',
        productos=productos,
        clientes=clientes
    )

@app.route('/api/ventas/pedidos/crear', methods=['POST'])
def api_crear_pedido():
    """
    Endpoint para crear pedido usando SP pedidoCrear.
    - Si viene id_cliente en el JSON, el pedido se crea a nombre de ese cliente.
    - Si no viene, se usa el usuario de la sesión (cliente que compra desde el catálogo).
    """
    print("\n" + "="*80)    
    try:
        data = request.get_json() or {}
        items = data.get('items', [])
        id_cliente = data.get('id_cliente')       
        print(f"  - items: {items}")
        print(f"  - id_cliente: {id_cliente}")
        print(f"  - session user_id: {session.get('user_id')}")
        print(f"  - session role: {session.get('role')}")

        if not items:           
            return jsonify({
                'success': False,
                'mensaje': 'El pedido debe tener al menos un producto'
            }), 400

        cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)        # Determinar usuario dueño del pedido
        if id_cliente:
            cur.callproc('sp_cliente_obtener_usuario', [id_cliente])
            fila_cli = cur.fetchone()
            while cur.nextset():
                pass           
            if not fila_cli or not fila_cli.get('id_usuario'):
                cur.close()               
                return jsonify({
                    'success': False,
                    'mensaje': 'El cliente seleccionado no tiene un usuario asociado válido.'
                }), 400
            id_usuario_pedido = fila_cli['id_usuario']       
        else:
            id_usuario_pedido = session.get('user_id')            
            if not id_usuario_pedido:
                cur.close()                
                return jsonify({
                    'success': False,
                    'mensaje': 'Sesión inválida. Vuelva a iniciar sesión.'
                }), 401

        # Verificar datos del usuario antes de crear el pedido usando SP
        cur.callproc('sp_usuario_datos', [id_usuario_pedido])
        usuario_data = cur.fetchone()
        while cur.nextset():
            pass       
        print(f"  - id_usuario: {usuario_data.get('id_usuario') if usuario_data else 'None'}")
        print(f"  - rfc_usuario: {usuario_data.get('rfc_usuario') if usuario_data else 'None'}")
        print(f"  - id_direccion: {usuario_data.get('id_direccion') if usuario_data else 'None'}")
        print(f"  - telefono: {usuario_data.get('telefono') if usuario_data else 'None'}")
        print(f"  - id_cliente: {usuario_data.get('id_cliente') if usuario_data else 'None'}")
        
        if not usuario_data:
            cur.close()            
            return jsonify({
                'success': False,
                'mensaje': 'Usuario no encontrado en el sistema.'
            }), 400

        # Tablas temporales       
        cur.execute("""
            CREATE TEMPORARY TABLE IF NOT EXISTS TmpPedidos (
                id_tmp_pedido INT AUTO_INCREMENT PRIMARY KEY,
                fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP,
                id_usuario INT NULL
            )
        """)
        cur.execute("""
            CREATE TEMPORARY TABLE IF NOT EXISTS TmpItems_Pedido (
                id_tmp_item INT AUTO_INCREMENT PRIMARY KEY,
                id_producto INT NOT NULL,
                cantidad_producto INT NOT NULL,
                id_tmp_pedido INT NOT NULL
            )
        """)
        
        # Encabezado temporal usando SP
        cur.callproc('sp_tmp_pedido_insertar', [id_usuario_pedido])
        resultado_tmp = cur.fetchone()
        while cur.nextset():
            pass
        id_tmp_pedido = resultado_tmp.get('id_tmp_pedido', 0) if resultado_tmp else cur.lastrowid
        
        # Items temporales usando SP
        items_insertados = 0
        for item in items:
            id_producto = item.get('id_producto')
            cantidad = int(item.get('cantidad', 1))
            if id_producto and cantidad > 0:
                cur.callproc('sp_tmp_item_pedido_insertar', [id_producto, cantidad, id_tmp_pedido])
                while cur.nextset():
                    pass
                items_insertados += 1
        
        # Verificar que los items se insertaron correctamente usando SP
        cur.callproc('sp_tmp_items_pedido_count', [id_tmp_pedido])
        verif_items = cur.fetchone()
        while cur.nextset():
            pass

        # Ejecutar SP
        try:
            cur.callproc('pedidoCrear', [id_tmp_pedido])
            # Consumir todos los resultados del SP (si los hay)
            while cur.nextset():
                pass
        except Exception as sp_error:
            import traceback
            traceback.print_exc()
            mysql.connection.rollback()
            cur.close()
            raise sp_error

        # Obtener pedido creado usando SP
        cur.callproc('sp_pedido_max_id', [])
        res = cur.fetchone()
        while cur.nextset():
            pass
        id_pedido = res.get('id_pedido', 0) if res else 0
        
        # Obtener factura si existe usando SP
        id_factura = None
        try:
            cur.callproc('sp_factura_por_pedido', [id_pedido])
            factura = cur.fetchone()
            while cur.nextset():
                pass
            if factura:
                id_factura = factura.get('id_factura')
        except Exception as fact_error:
            pass
        
        mysql.connection.commit()
        cur.close()

        return jsonify({
            'success': True,
            'mensaje': 'Pedido creado exitosamente',
            'id_pedido': id_pedido,
            'id_factura': id_factura
        })

    except Exception as e:
        import traceback
        error_str = str(e)
        traceback.print_exc()
        
        # Hacer rollback si hay una conexión activa
        try:
            mysql.connection.rollback()
        except Exception as rollback_error:
            pass        # Mapear errores del SP a mensajes amigables
        mensaje_usuario = 'Error al crear el pedido. Verifique que haya stock disponible y que el usuario/cliente sean válidos.'
        
        if 'ERROR_CARRITO_INVALIDO' in error_str:
            mensaje_usuario = 'Error: El carrito es inválido. Por favor, recargue la página e intente nuevamente.'
        elif 'ERROR_CARRITO_VACIO' in error_str:
            mensaje_usuario = 'Error: El pedido debe tener al menos un producto.'
        elif 'ERROR_SIN_CLIENTE' in error_str:
            mensaje_usuario = 'Error: El usuario seleccionado no tiene un cliente asociado. Contacte al administrador.'
        elif 'ERROR_FALTA_RFC' in error_str:
            mensaje_usuario = 'Error: El cliente no tiene RFC registrado. Por favor, complete los datos del cliente antes de crear el pedido.'
        elif 'ERROR_FALTA_DIRECCION' in error_str:
            mensaje_usuario = 'Error: El cliente no tiene dirección registrada. Por favor, complete los datos del cliente antes de crear el pedido.'
        elif 'ERROR_FALTA_TELEFONO' in error_str:
            mensaje_usuario = 'Error: El cliente no tiene teléfono registrado. Por favor, complete los datos del cliente antes de crear el pedido.'
        elif 'ERROR_STOCK_INSUFICIENTE' in error_str:
            mensaje_usuario = 'Error: No hay stock suficiente para uno o más productos del pedido. Verifique el inventario disponible.'
        elif 'ERROR_ESTADO_NO_EXISTE' in error_str:
            mensaje_usuario = 'Error: El estado "Confirmado" no existe en el sistema. Contacte al administrador.'
        elif 'OperationalError' in error_str or '1644' in error_str:
            # Error de MySQL SIGNAL
            import re
            match = re.search(r'["\']([^"\']+)["\']', error_str)
            if match:
                mensaje_usuario = match.group(1)
        
        return jsonify({
            'success': False,
            'mensaje': mensaje_usuario,
            'error': error_str
        }), 500

@app.route('/inventario/catalogo')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def inventario_catalogo():
    """Catálogo de productos para inventario"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener todos los productos con información completa
        cursor.callproc('sp_productos_catalogo_inventario', [])
        productos = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('inventario_catalogo.html', productos=productos)
    except Exception as e:
        import traceback
        print(f"Error cargando catálogo inventario: {str(e)}\n{traceback.format_exc()}")
        return render_template('inventario_catalogo.html', productos=[])

@app.route('/inventario/inventario')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def inventario_inventario():
    """Gestión de inventario para rol Inventarios - Replica exacta de admin/inventario"""
    import MySQLdb.cursors

    # 1. Obtener inventario por producto (SP que ya tienes)
    cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur.callproc("admin_inventario_productos")
    productos = cur.fetchall()
    while cur.nextset():
        pass
    cur.close()

    # 2. Obtener sucursales para el filtro usando SP
    cur2 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    cur2.callproc('sp_sucursales_activas', [])
    sucursales = cur2.fetchall()
    while cur2.nextset():
        pass
    cur2.close()

    # 3. Obtener la sucursal del usuario actual usando SP
    # Para Gestor de Sucursal, obtener específicamente la sucursal de ese rol
    sucursal_usuario = None
    id_usuario = session.get('user_id')
    if id_usuario:
        cur3 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        # Primero intentar obtener la sucursal del rol "Gestor de Sucursal" si el usuario tiene ese rol
        cur3.callproc('sp_usuario_sucursal_por_rol', [id_usuario, 'Gestor de Sucursal'])
        resultado_sucursal = cur3.fetchone()
        while cur3.nextset():
            pass
        if resultado_sucursal:
            sucursal_usuario = resultado_sucursal['nombre_sucursal']
        else:
            # Si no tiene sucursal como Gestor de Sucursal, buscar cualquier sucursal asignada
            cur3.callproc('sp_usuario_sucursal', [id_usuario])
            resultado_sucursal = cur3.fetchone()
            if resultado_sucursal:
                sucursal_usuario = resultado_sucursal['nombre_sucursal']
        cur3.close()
    
    # Si no tiene sucursal asignada, usar la primera sucursal activa
    # NOTA: Para Gestor de Sucursal, esto no debería pasar, pero lo dejamos como fallback
    if not sucursal_usuario and sucursales:
        sucursal_usuario = sucursales[0]['nombre_sucursal']

    # 4. Pasar también el usuario (si tu base.html lo usa)
    user = {
        "full_name": session.get("full_name", "Usuario"),
        "role": session.get("role", "Inventarios")
    }

    return render_template(
        'inventario_inventario.html',
        productos=productos,
        sucursales=sucursales,
        sucursal_usuario=sucursal_usuario,
        user=user
    )

@app.route('/inventario/reportes')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def inventario_reportes():
    """Reportes específicos para Gestor de Sucursal - Datos de su sucursal"""
    import MySQLdb.cursors
    
    # Obtener la sucursal del usuario actual
    id_usuario = session.get('user_id')
    id_sucursal = None
    nombre_sucursal = None
    
    if id_usuario:
        cur = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        # Primero intentar obtener la sucursal del rol "Gestor de Sucursal"
        try:
            cur.callproc('sp_usuario_sucursal_por_rol', [id_usuario, 'Gestor de Sucursal'])
            resultado_sucursal = cur.fetchone()
            while cur.nextset():
                pass
            if resultado_sucursal:
                id_sucursal = resultado_sucursal.get('id_sucursal')
                nombre_sucursal = resultado_sucursal.get('nombre_sucursal')
        except:
            pass
        
        if not id_sucursal:
            # Si no tiene sucursal como Gestor de Sucursal, buscar cualquier sucursal asignada
            try:
                cur.callproc('sp_usuario_sucursal', [id_usuario])
                resultado_sucursal = cur.fetchone()
                while cur.nextset():
                    pass
                if resultado_sucursal:
                    id_sucursal = resultado_sucursal.get('id_sucursal')
                    nombre_sucursal = resultado_sucursal.get('nombre_sucursal')
            except:
                pass
        cur.close()
    
    user = {
        "full_name": session.get("full_name", "Usuario"),
        "role": session.get("role", "Gestor de Sucursal")
    }
    
    return render_template(
        'inventario_reportes.html',
        id_sucursal=id_sucursal,
        nombre_sucursal=nombre_sucursal,
        user=user
    )

@app.route('/inventario/devoluciones')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def inventario_devoluciones():
    """Gestión de devoluciones para inventario - Replica exacta de admin/devoluciones"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener devoluciones con información completa usando SP
        cursor.callproc('sp_devoluciones_lista_admin', [])
        devoluciones = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('inventario_devoluciones.html', devoluciones=devoluciones)
    except Exception as e:
        import traceback
        print(f"Error cargando devoluciones: {str(e)}\n{traceback.format_exc()}")
        return render_template('inventario_devoluciones.html', devoluciones=[])

@app.route('/api/inventario/devoluciones/<int:id_devolucion>/reingresar', methods=['POST'])
def api_reingresar_devolucion(id_devolucion):
    """Endpoint para reingresar devolución al inventario usando SOLO SP reingresoInventario - SIN SQL EMBEBIDO"""
    try:
        # Obtener id_usuario_rol del usuario actual
        user_id = session.get('user_id')
        if not user_id:
            return jsonify({'error': 'Usuario no autenticado'}), 401
        
        cursor = mysql.connection.cursor()
        
        # Obtener id_usuario_rol del usuario actual usando SP
        cursor.callproc('sp_usuario_rol_inventario', [user_id])
        usuario_rol_result = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not usuario_rol_result:
            # Si no encuentra con rol inventario, usar el primer usuario_rol activo del usuario
            cursor.callproc('sp_usuario_rol_primero_activo', [user_id])
            usuario_rol_result = cursor.fetchone()
            while cursor.nextset():
                pass
        
        if not usuario_rol_result:
            cursor.close()
            return jsonify({'error': 'No se encontró un rol de usuario válido para realizar el reingreso'}), 400
        
        id_usuario_rol = usuario_rol_result.get('id_usuario_rol', 0)
        
        # Llamar al SP reingresoInventario - SOLO SP, NO SQL EMBEBIDO
        # Parámetros: id_devolucionSP, id_usuario_rolSP
        # El SP valida:
        # - Que la devolución exista
        # - Que esté en estado "Autorizado"
        # - Que el tipo NO sea "Cambio"
        # - Crea registros en Cambios_Sucursal y Tipo_Entradas
        cursor.callproc('reingresoInventario', [
            int(id_devolucion),
            int(id_usuario_rol)
        ])
        
        # El SP no retorna un SELECT, solo hace los INSERTs
        # Asegurar que el commit se refleje
        mysql.connection.commit()
        cursor.close()
        
        return jsonify({
            'success': True,
            'mensaje': 'Productos reingresados al inventario exitosamente'
        })
    except Exception as e:
        import traceback
        error_msg = f"Error reingresando devolución: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Extraer mensaje de error del SP si es posible
        error_str = str(e)
        mensaje_usuario = 'Error al reingresar productos al inventario.'
        
        # Intentar extraer mensaje más específico del error
        if 'ERROR:' in error_str:
            parts = error_str.split('ERROR:', 1)
            if len(parts) > 1:
                mensaje_usuario = parts[1].strip()
        elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
            if ':' in error_str:
                mensaje_usuario = error_str.split(':', 1)[-1].strip()
        elif 'no está autorizada' in error_str.lower() or 'no existe el estado autorizado' in error_str.lower():
            mensaje_usuario = 'La devolución no está autorizada. El SP requiere que exista un estado "Autorizado" en la tabla estados_devoluciones. Verifique la configuración de la base de datos.'
        elif 'tipo Cambio' in error_str.lower() or 'tipo cambio' in error_str.lower():
            mensaje_usuario = 'Las devoluciones de tipo "Cambio" no generan reingreso a inventario.'
        elif 'no existe' in error_str.lower() or 'not found' in error_str.lower():
            mensaje_usuario = 'La devolución no fue encontrada.'
        
        return jsonify({
            'success': False,
            'error': str(e),
            'mensaje': mensaje_usuario
        }), 500

@app.route('/inventario/devoluciones/crear')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def inventario_crear_devolucion():
    """Página para crear nueva devolución - inventario"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener pedidos con detalles para devolución usando SP
        cursor.callproc('sp_pedidos_para_devolucion_limitado', [50])
        pedidos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener tipos y motivos de devolución usando SP tiposMotivosDevolucion - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('tiposMotivosDevolucion', [])
        tipos_devolucion = cursor.fetchall()  # Primer result set: tipos de devolución
        cursor.nextset()  # Avanzar al segundo result set
        motivos_devolucion_raw = cursor.fetchall()  # Segundo result set: motivos de devolución
        # Consumir todos los resultados del SP
        while cursor.nextset():
            pass
        
        # Convertir motivos_devolucion de lista de diccionarios a lista de strings
        motivos_devolucion = [motivo['motivo_devolucion'] for motivo in motivos_devolucion_raw] if motivos_devolucion_raw else []
        
        cursor.close()
        
        return render_template('inventario_crear_devolucion.html', 
                            pedidos=pedidos, 
                            tipos_devolucion=tipos_devolucion,
                            motivos_devolucion=motivos_devolucion)
    except Exception as e:
        import traceback
        print(f"Error cargando página crear devolución inventario: {str(e)}\n{traceback.format_exc()}")
        return render_template('inventario_crear_devolucion.html', pedidos=[], tipos_devolucion=[], motivos_devolucion=[])

@app.route('/api/inventario/devoluciones/pedido/<int:id_pedido>/productos')
def api_inventario_obtener_productos_pedido(id_pedido):
    """Obtener productos de un pedido para devolución - inventario (misma funcionalidad que ventas)"""
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("""
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
            WHERE pd.id_pedido = %s
        """, (id_pedido,))
        productos = cursor.fetchall()
        cursor.close()
        
        return jsonify(productos)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/inventario/devoluciones/crear', methods=['POST'])
def api_inventario_crear_devolucion():
    """Endpoint para crear devolución usando SP devolucionCrear - inventario (mismo SP que ventas)"""
    try:
        data = request.get_json()
        id_pedido = data.get('id_pedido')
        items = data.get('items', [])
        
        if not id_pedido:
            return jsonify({'error': 'ID de pedido requerido'}), 400
        
        if not items or len(items) == 0:
            return jsonify({'error': 'Debe seleccionar al menos un producto para devolver'}), 400
        
        # Preparar JSON para el SP (formato esperado por devolucionCrear)
        # El SP espera: id_producto (INT), cantidad (INT), motivo (VARCHAR), id_tipo_devolucion (INT)
        items_json = []
        for item in items:
            # Asegurar que los valores sean del tipo correcto (enteros para id_producto, cantidad, id_tipo_devolucion)
            id_producto = int(item.get('id_producto', 0))
            cantidad = int(item.get('cantidad', 1))
            motivo = str(item.get('motivo', '')).strip()
            id_tipo_devolucion = int(item.get('id_tipo_devolucion', 1))
            
            if id_producto <= 0:
                return jsonify({'error': 'ID de producto inválido'}), 400
            if cantidad <= 0:
                return jsonify({'error': 'La cantidad debe ser mayor a 0'}), 400
            
            items_json.append({
                'id_producto': id_producto,
                'cantidad': cantidad,
                'motivo': motivo,
                'id_tipo_devolucion': id_tipo_devolucion
            })
        
        import json
        items_json_str = json.dumps(items_json, ensure_ascii=False)        
        print(f"  - id_pedido: {id_pedido}")
        print(f"  - items_json: {items_json_str}")
        
        cursor = mysql.connection.cursor()
        
        try:
            # Llamar al SP devolucionCrear (mismo que usa ventas)
            # Parámetros: p_id_pedido (INT), p_items_json (TEXT)
            cursor.callproc('devolucionCrear', [int(id_pedido), items_json_str])
            
            # Leer el resultado del SP (el SELECT que retorna)
            id_devolucion = None
            
            try:
                resultado = cursor.fetchone()               
                if resultado:
                    # El SP retorna: SELECT v_id_devolucion AS id_devolucion_generada
                    if isinstance(resultado, dict):
                        id_devolucion = resultado.get('id_devolucion_generada', 0)
                    else:
                        id_devolucion = resultado[0] if resultado else 0        
                
                # IMPORTANTE: Consumir todos los result sets restantes para evitar "Commands out of sync"
                while cursor.nextset():
                    pass
                    
            except Exception as e:                
                import traceback
                print(f"Error leyendo resultado del SP: {e}\n{traceback.format_exc()}")
                # Aún así, consumir todos los result sets
                try:
                    while cursor.nextset():
                        pass
                except:
                    pass
            
            # Si no se pudo obtener del resultado, obtener el último ID insertado
            # PERO primero debemos asegurarnos de que todos los result sets estén consumidos
            if not id_devolucion or id_devolucion == 0:
                # Crear un nuevo cursor para evitar problemas de sincronización
                cursor.close()
                cursor2 = mysql.connection.cursor()
                cursor2.callproc('sp_devolucion_max_id', [])
                resultado_max = cursor2.fetchone()
                while cursor2.nextset():
                    pass
                id_devolucion = resultado_max.get('id_devolucion', 0) if resultado_max else 0
                cursor2.close()
            
            # Asegurar que el commit se refleje
            mysql.connection.commit()
            
        except Exception as sp_error:
            # Hacer rollback en caso de error
            try:
                mysql.connection.rollback()
            except:
                pass
            # Intentar consumir result sets antes de cerrar
            try:
                while cursor.nextset():
                    pass
            except:
                pass
            # Cerrar cursor antes de relanzar el error
            try:
                cursor.close()
            except:
                pass
            # Relanzar el error para que sea capturado por el except externo
            raise sp_error
        finally:
            # Asegurar que el cursor se cierre siempre
            try:
                # Intentar consumir result sets antes de cerrar
                try:
                    while cursor.nextset():
                        pass
                except:
                    pass
                cursor.close()
            except:
                pass
        
        return jsonify({
            'success': True,
            'mensaje': 'Devolución creada exitosamente',
            'id_devolucion': id_devolucion
        })
    except Exception as e:
        import traceback
        error_msg = f"Error creando devolución: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Extraer mensaje de error del trigger/SP si es posible
        error_str = str(e)
        mensaje_usuario = 'Error al crear la devolución.'
        
        # Intentar extraer mensaje más específico del error
        if 'Error:' in error_str:
            # Si el SP retorna un error con "Error:" al inicio (SIGNAL SQLSTATE)
            parts = error_str.split('Error:', 1)
            if len(parts) > 1:
                mensaje_usuario = parts[1].strip()
            else:
                mensaje_usuario = error_str
        elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
            # Intentar extraer mensaje más amigable
            if ':' in error_str:
                mensaje_usuario = error_str.split(':', 1)[-1].strip()
            else:
                mensaje_usuario = error_str
        elif 'does not belong' in error_str.lower() or 'no pertenece' in error_str.lower():
            mensaje_usuario = 'Uno de los productos no pertenece al pedido seleccionado.'
        elif 'cantidad mayor' in error_str.lower() or 'cantidad' in error_str.lower():
            mensaje_usuario = 'La cantidad a devolver no puede ser mayor a la cantidad comprada.'
        else:
            # Usar el mensaje completo si no hay formato específico (limitado a 200 caracteres)
            mensaje_usuario = error_str if len(error_str) < 200 else error_str[:200] + '...'
        
        return jsonify({
            'success': False,
            'error': str(e),
            'mensaje': mensaje_usuario,
            'traceback': traceback.format_exc() if app.debug else None
        }), 500

@app.route('/finanzas')
@login_requerido
@requiere_rol('Analista Financiero')
def finanzas():
    """Panel de finanzas - solo para Analista Financiero"""
    return render_template('finanzas_dashboard.html')

@app.route('/finanzas/pedidos')
@login_requerido
@requiere_rol('Analista Financiero')
def finanzas_pedidos():
    """Página de pedidos para Analista Financiero - con información de pagos"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener pedidos con información de facturas y pagos
        cursor.callproc('sp_finanzas_pedidos_lista', [])
        pedidos = cursor.fetchall()
        while cursor.nextset():
            pass
        while cursor.nextset():
            pass
        
        cursor.close()
        
        return render_template('finanzas_pedidos.html', pedidos=pedidos)
    except Exception as e:
        import traceback
        print(f"Error cargando pedidos finanzas: {str(e)}\n{traceback.format_exc()}")
        return render_template('finanzas_pedidos.html', pedidos=[])

@app.route('/api/finanzas/pedidos/<int:id_pedido>/detalles')
@login_requerido
@requiere_rol('Analista Financiero')
def api_finanzas_detalles_pedido(id_pedido):
    """API para obtener detalles de un pedido específico"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener información del pedido
        cursor.execute("""
            SELECT 
                p.id_pedido,
                p.fecha_pedido,
                ep.estado_pedido,
                COALESCE((
                    SELECT SUM(pd.cantidad_producto * pr.precio_unitario)
                    FROM Pedidos_Detalles pd
                    JOIN Productos pr ON pd.id_producto = pr.id_producto
                    WHERE pd.id_pedido = p.id_pedido
                ), 0) AS total_pedido,
                CONCAT(
                    IFNULL(u.nombre_primero, ''), ' ',
                    IFNULL(u.nombre_segundo, ''), ' ',
                    IFNULL(u.apellido_paterno, ''), ' ',
                    IFNULL(u.apellido_materno, '')
                ) AS nombre_cliente
            FROM Pedidos p
            LEFT JOIN Estados_Pedidos ep ON p.id_estado_pedido = ep.id_estado_pedido
            LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
            LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
            LEFT JOIN Usuarios u ON c.id_usuario = u.id_usuario
            WHERE p.id_pedido = %s
        """, (id_pedido,))
        pedido = cursor.fetchone()
        
        if not pedido:
            cursor.close()
            return jsonify({'error': 'Pedido no encontrado'}), 404
        
        # Obtener productos del pedido
        cursor.execute("""
            SELECT 
                pd.id_pedido_detalle,
                pd.cantidad_producto,
                pr.precio_unitario,
                m.nombre_producto,
                s.sku
            FROM Pedidos_Detalles pd
            JOIN Productos pr ON pd.id_producto = pr.id_producto
            JOIN Modelos m ON pr.id_modelo = m.id_modelo
            JOIN Sku s ON pr.id_sku = s.id_sku
            WHERE pd.id_pedido = %s
        """, (id_pedido,))
        productos = cursor.fetchall()
        
        cursor.close()
        
        pedido['productos'] = productos
        pedido['fecha_pedido'] = pedido['fecha_pedido'].strftime('%d/%m/%Y') if pedido['fecha_pedido'] else 'N/A'
        
        return jsonify(pedido)
    except Exception as e:
        import traceback
        print(f"Error obteniendo detalles del pedido: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': 'Error al obtener los detalles del pedido'}), 500

@app.route('/api/finanzas/facturas/<int:id_factura>/pagos')
@login_requerido
@requiere_rol('Analista Financiero')
def api_finanzas_pagos_factura(id_factura):
    """API para obtener pagos asociados a una factura"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener información de la factura
        cursor.callproc('sp_factura_info_pagos', [id_factura])
        factura = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not factura:
            cursor.close()
            return jsonify({'error': 'Factura no encontrada'}), 404
        
        # Obtener pagos de la factura
        cursor.callproc('sp_factura_pagos_lista', [id_factura])
        pagos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Convertir fechas a string
        for pago in pagos:
            if pago['fecha_pago']:
                pago['fecha_pago'] = pago['fecha_pago'].strftime('%d/%m/%Y')
        
        cursor.close()
        
        factura['pagos'] = pagos
        
        return jsonify(factura)
    except Exception as e:
        import traceback
        print(f"Error obteniendo pagos de la factura: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': 'Error al obtener los pagos de la factura'}), 500

@app.route('/finanzas/pagos')
@login_requerido
@requiere_rol('Analista Financiero')
def finanzas_pagos():
    """Página de gestión de pagos y cuentas por cobrar para Analista Financiero"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener pagos recibidos (todos los pagos registrados)
        cursor.execute("""
            SELECT 
                p.id_pago,
                p.id_factura,
                p.id_pedido,
                p.fecha_pago,
                f.folio,
                f.total as total_factura,
                mp.monto_metodo_pago,
                mp2.nombre_metodo_pago,
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
                ) as nombre_cliente,
                pe.fecha_pedido
            FROM Pagos p
            INNER JOIN Facturas f ON p.id_factura = f.id_factura
            INNER JOIN Pedidos pe ON p.id_pedido = pe.id_pedido
            LEFT JOIN Pedidos_Clientes pc ON pe.id_pedido = pc.id_pedido
            LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
            LEFT JOIN Usuarios u ON c.id_usuario = u.id_usuario
            LEFT JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
            LEFT JOIN Metodos_Pagos mp2 ON mp.id_metodo_pago = mp2.id_metodo_pago
            ORDER BY p.fecha_pago DESC, p.id_pago DESC
            LIMIT 500
        """)
        pagos_recibidos = cursor.fetchall()
        
        # Obtener pagos pendientes (facturas no completamente pagadas)
        cursor.execute("""
            SELECT 
                f.id_factura,
                f.folio,
                f.id_pedido,
                f.fecha_emision,
                f.total,
                COALESCE(SUM(mp.monto_metodo_pago), 0) as total_pagado,
                (f.total - COALESCE(SUM(mp.monto_metodo_pago), 0)) as pendiente,
                DATE_ADD(f.fecha_emision, INTERVAL 30 DAY) as fecha_limite_cobro,
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
                ) as nombre_cliente,
                CASE 
                    WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total THEN 'Pagada'
                    WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) > 0 THEN 'Parcial'
                    ELSE 'Pendiente'
                END as estado_pago
            FROM Facturas f
            INNER JOIN Pedidos pe ON f.id_pedido = pe.id_pedido
            LEFT JOIN Pedidos_Clientes pc ON pe.id_pedido = pc.id_pedido
            LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
            LEFT JOIN Usuarios u ON c.id_usuario = u.id_usuario
            LEFT JOIN Pagos pa ON f.id_factura = pa.id_factura
            LEFT JOIN Montos_Pagos mp ON pa.id_pago = mp.id_pago
            GROUP BY 
                f.id_factura, f.folio, f.id_pedido, f.fecha_emision, f.total,
                u.nombre_primero, u.nombre_segundo, u.apellido_paterno, u.apellido_materno
            HAVING pendiente > 0
            ORDER BY f.fecha_emision DESC, f.id_factura DESC
            LIMIT 500
        """)
        pagos_pendientes = cursor.fetchall()
        
        # Obtener métodos de pago usando SP
        cursor.callproc('sp_metodos_pago_lista_nombre', [])
        metodos_pago = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        # Decodificar datos
        pagos_recibidos_decoded = []
        for row in pagos_recibidos:
            decoded = decode_row(row)
            if decoded:
                pagos_recibidos_decoded.append(decoded)
        
        pagos_pendientes_decoded = []
        for row in pagos_pendientes:
            decoded = decode_row(row)
            if decoded:
                pagos_pendientes_decoded.append(decoded)
        
        metodos_pago_decoded = []
        for row in metodos_pago:
            decoded = decode_row(row)
            if decoded:
                metodos_pago_decoded.append(decoded)
        
        return render_template(
            'finanzas_pagos.html',
            pagos_recibidos=pagos_recibidos_decoded,
            pagos_pendientes=pagos_pendientes_decoded,
            metodos_pago=metodos_pago_decoded
        )
    except Exception as e:
        import traceback
        print(f"Error cargando pagos: {str(e)}\n{traceback.format_exc()}")
        return render_template(
            'finanzas_pagos.html',
            pagos_recibidos=[],
            pagos_pendientes=[],
            metodos_pago=[]
        )

@app.route('/finanzas/facturas')
@login_requerido
@requiere_rol('Analista Financiero')
def finanzas_facturas():
    """Gestión de facturas para Analista Financiero - Replica exacta de admin/facturas"""
    try:
        # Obtener parámetros de filtro de la URL
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or None
        fecha_fin = request.args.get('fecha_fin', '').strip() or None
        busqueda = request.args.get('busqueda', '').strip() or None
        
        # Convertir fechas de string a date si están presentes
        fecha_inicio_date = None
        fecha_fin_date = None
        
        if fecha_inicio:
            try:
                fecha_inicio_date = datetime.strptime(fecha_inicio, '%Y-%m-%d').date()
            except ValueError:
                fecha_inicio_date = None
        
        if fecha_fin:
            try:
                fecha_fin_date = datetime.strptime(fecha_fin, '%Y-%m-%d').date()
            except ValueError:
                fecha_fin_date = None
        
        # Configurar charset en la conexión antes de crear el cursor
        try:
            mysql.connection.ping()
        except:
            # Si la conexión está cerrada, se reconectará automáticamente al hacer la siguiente query
            pass
        
        # Verificar si el stored procedure existe y cuántas facturas hay
        import MySQLdb.cursors
        cursor_check = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor_check.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")
        
        cursor_check.execute("""
            SELECT ROUTINE_NAME 
            FROM information_schema.ROUTINES 
            WHERE ROUTINE_SCHEMA = DATABASE() 
            AND ROUTINE_NAME = 'admin_facturas_lista'
        """)
        sp_exists = cursor_check.fetchone()       
        cursor_check.callproc('sp_facturas_count', [])
        total_facturas = cursor_check.fetchone()
        while cursor_check.nextset():
            pass
        print(f"[DEBUG finanzas_facturas] Total facturas en BD: {total_facturas.get('total', 0) if total_facturas else 0}")
        
        # Verificar si hay facturas con pedidos asociados
        cursor_check.execute("""
            SELECT COUNT(*) as total 
            FROM Facturas f 
            INNER JOIN Pedidos p ON f.id_pedido = p.id_pedido
        """)
        facturas_con_pedidos = cursor_check.fetchone()
        print(f"[DEBUG finanzas_facturas] Facturas con pedidos asociados: {facturas_con_pedidos.get('total', 0) if facturas_con_pedidos else 0}")
        cursor_check.close()
        
        # Crear un cursor nuevo para el stored procedure usando DictCursor
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")
        
        # Obtener facturas usando SP admin_facturas_lista - SOLO SP, NO SQL EMBEBIDO
        facturas = []
        try:
            print(f"[DEBUG finanzas_facturas] Llamando SP admin_facturas_lista con: fecha_inicio={fecha_inicio_date}, fecha_fin={fecha_fin_date}, busqueda={busqueda}")
            # Llamar al stored procedure
            cursor.callproc('admin_facturas_lista', [fecha_inicio_date, fecha_fin_date, busqueda])
            
            # Obtener el primer result set
            facturas_raw = cursor.fetchall()
            print(f"[DEBUG finanzas_facturas] Facturas obtenidas del SP: {len(facturas_raw)}")
            
            # Consumir todos los result sets adicionales
            while cursor.nextset():
                pass
            
            # Convertir los datos y manejar codificación
            for row in facturas_raw:
                try:
                    decoded_row = decode_row(row)
                    if decoded_row:
                        # Asegurar que fecha_emision sea date si viene como string
                        if 'fecha_emision' in decoded_row and decoded_row['fecha_emision']:
                            if isinstance(decoded_row['fecha_emision'], str):
                                try:
                                    decoded_row['fecha_emision'] = datetime.strptime(decoded_row['fecha_emision'], '%Y-%m-%d').date()
                                except:
                                    try:
                                        decoded_row['fecha_emision'] = datetime.strptime(decoded_row['fecha_emision'], '%Y-%m-%d %H:%M:%S').date()
                                    except:
                                        pass
                        facturas.append(decoded_row)
                except Exception as decode_error:
                    import traceback
                    traceback.print_exc()
            if len(facturas) == 0 and total_facturas and total_facturas.get('total', 0) > 0:
                # Usar DictCursor para la consulta fallback también
                cursor_fallback = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
                cursor_fallback.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")
                cursor_fallback.execute("""
                    SELECT 
                        f.id_factura,
                        f.folio,
                        f.id_pedido,
                        f.fecha_emision,
                        f.subtotal,
                        f.impuestos,
                        f.total,
                        COALESCE(ef.estado_factura, 'Emitida') as estado_factura,
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
                        ) as nombre_cliente,
                        u.nombre_usuario,
                        COALESCE(SUM(mp.monto_metodo_pago), 0) as total_pagado,
                        (f.total - COALESCE(SUM(mp.monto_metodo_pago), 0)) as pendiente,
                        CASE 
                            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total THEN 'Pagada'
                            WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) > 0 THEN 'Parcial'
                            ELSE 'Pendiente'
                        END as estado_pago,
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
                        (%s IS NULL OR f.fecha_emision >= %s)
                        AND (%s IS NULL OR f.fecha_emision <= %s)
                    GROUP BY 
                        f.id_factura, f.folio, f.id_pedido, f.fecha_emision, 
                        f.subtotal, f.impuestos, f.total, ef.estado_factura,
                        u.nombre_primero, u.nombre_segundo, u.apellido_paterno, 
                        u.apellido_materno, u.nombre_usuario, p.fecha_pedido
                    ORDER BY f.fecha_emision DESC, f.id_factura DESC
                    LIMIT 500
                """, (fecha_inicio_date, fecha_inicio_date, fecha_fin_date, fecha_fin_date))
                facturas_fallback = cursor_fallback.fetchall()
                for row in facturas_fallback:
                    decoded_row = decode_row(row)
                    if decoded_row:
                        facturas.append(decoded_row)
                cursor_fallback.close()
                        
        except Exception as sp_error:
            import traceback
            error_msg = f"[ERROR] Error ejecutando stored procedure: {str(sp_error)}\n{traceback.format_exc()}"
            print(error_msg)
            facturas = []
        
        cursor.close()
        
        return render_template(
            'finanzas_facturas.html', 
            facturas=facturas,
            fecha_inicio=fecha_inicio or '',
            fecha_fin=fecha_fin or '',
            busqueda=busqueda or ''
        )
    except UnicodeDecodeError as e:
        import traceback
        error_msg = f"Error de codificación cargando facturas: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Obtener parámetros de filtro de la URL para el fallback
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or None
        fecha_fin = request.args.get('fecha_fin', '').strip() or None
        busqueda = request.args.get('busqueda', '').strip() or None
        
        fecha_inicio_date = None
        fecha_fin_date = None
        
        if fecha_inicio:
            try:
                fecha_inicio_date = datetime.strptime(fecha_inicio, '%Y-%m-%d').date()
            except ValueError:
                fecha_inicio_date = None
        
        if fecha_fin:
            try:
                fecha_fin_date = datetime.strptime(fecha_fin, '%Y-%m-%d').date()
            except ValueError:
                fecha_fin_date = None
        
        try:
            cursor = mysql.connection.cursor()
            cursor.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")
            cursor.callproc('admin_facturas_lista', [fecha_inicio_date, fecha_fin_date, busqueda])
            facturas_raw = cursor.fetchall()
            while cursor.nextset():
                pass
            
            facturas = []
            for row in facturas_raw:
                factura_dict = {}
                for key, value in row.items():
                    if isinstance(value, bytes):
                        factura_dict[key] = value.decode('utf-8', errors='replace')
                    else:
                        factura_dict[key] = value
                facturas.append(factura_dict)
            
            cursor.close()
            return render_template(
                'finanzas_facturas.html', 
                facturas=facturas,
                fecha_inicio=fecha_inicio or '',
                fecha_fin=fecha_fin or '',
                busqueda=busqueda or ''
            )
        except Exception as e2:
            print(f"Error en fallback: {str(e2)}")
            return render_template(
                'finanzas_facturas.html', 
                facturas=[],
                fecha_inicio=fecha_inicio or '',
                fecha_fin=fecha_fin or '',
                busqueda=busqueda or ''
            )
    except Exception as e:
        import traceback
        error_msg = f"Error cargando facturas: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or ''
        fecha_fin = request.args.get('fecha_fin', '').strip() or ''
        busqueda = request.args.get('busqueda', '').strip() or ''
        
        return render_template(
            'finanzas_facturas.html', 
            facturas=[],
            fecha_inicio=fecha_inicio,
            fecha_fin=fecha_fin,
            busqueda=busqueda
        )

@app.route('/finanzas/reportes')
@login_requerido
@requiere_rol('Analista Financiero')
def finanzas_reportes():
    """Página de reportes para Analista Financiero"""
    return render_template('finanzas_reportes.html')

# ========== API ENDPOINTS PARA REPORTES FINANCIEROS ==========

@app.route('/api/finanzas/reporte/resumen')
@login_requerido
@requiere_rol('Analista Financiero')
def api_finanzas_resumen():
    """Resumen financiero: ingresos totales, facturas, pagadas, pendiente"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Ingresos totales (suma de todas las facturas)
        cursor.execute("""
            SELECT COALESCE(SUM(total), 0) as ingresos_totales
            FROM Facturas
        """)
        ingresos = cursor.fetchone()
        ingresos_totales = float(ingresos.get('ingresos_totales', 0) if ingresos else 0)
        print(f"[DEBUG finanzas_resumen] Ingresos totales: {ingresos_totales}")
        
        # Total de facturas usando SP
        cursor.callproc('sp_facturas_count', [])
        total_facturas_result = cursor.fetchone()
        while cursor.nextset():
            pass
        total_facturas = total_facturas_result.get('total', 0) if total_facturas_result else 0
        print(f"[DEBUG finanzas_resumen] Total facturas: {total_facturas}")
        
        # Facturas pagadas (donde el total pagado >= total factura)
        cursor.callproc('sp_finanzas_facturas_pagadas_count', [])
        facturas_pagadas_result = cursor.fetchall()
        while cursor.nextset():
            pass
        facturas_pagadas = len(facturas_pagadas_result) if facturas_pagadas_result else 0
        print(f"[DEBUG finanzas_resumen] Facturas pagadas: {facturas_pagadas}")
        
        # Pendiente por cobrar (total facturas - total pagado)
        cursor.execute("""
            SELECT 
                COALESCE(SUM(f.total), 0) as total_facturado,
                COALESCE(SUM(mp.monto_metodo_pago), 0) as total_pagado
            FROM Facturas f
            LEFT JOIN Pagos p ON f.id_factura = p.id_factura
            LEFT JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
        """)
        pendiente_result = cursor.fetchone()
        total_facturado = float(pendiente_result.get('total_facturado', 0) if pendiente_result else 0)
        total_pagado = float(pendiente_result.get('total_pagado', 0) if pendiente_result else 0)
        pendiente_cobrar = max(0, total_facturado - total_pagado)
        print(f"[DEBUG finanzas_resumen] Total facturado: {total_facturado}, Total pagado: {total_pagado}, Pendiente: {pendiente_cobrar}")
        
        cursor.close()
        
        resultado = {
            'ingresos_totales': ingresos_totales,
            'total_facturas': total_facturas,
            'facturas_pagadas': facturas_pagadas,
            'pendiente_cobrar': max(0, pendiente_cobrar)
        }
        print(f"[DEBUG finanzas_resumen] Resultado final: {resultado}")
        return jsonify(resultado)
    except Exception as e:
        import traceback
        error_msg = f"Error en resumen financiero: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'ingresos_totales': 0,
            'total_facturas': 0,
            'facturas_pagadas': 0,
            'pendiente_cobrar': 0
        }), 200

@app.route('/api/finanzas/reporte/facturacion-anio')
@login_requerido
@requiere_rol('Analista Financiero')
def api_finanzas_facturacion_anio():
    """Facturación agrupada por año (últimos 5 años)"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener facturación por año para los últimos 5 años
        cursor.execute("""
            SELECT 
                YEAR(f.fecha_emision) as anio,
                COALESCE(SUM(f.total), 0) as total
            FROM Facturas f
            WHERE f.fecha_emision >= DATE_SUB(CURDATE(), INTERVAL 5 YEAR)
            GROUP BY YEAR(f.fecha_emision)
            ORDER BY anio DESC
            LIMIT 5
        """)
        
        resultados = cursor.fetchall()
        print(f"[DEBUG finanzas_facturacion_anio] Resultados últimos 5 años: {len(resultados)}")
        
        if not resultados:
            # Si no hay datos en los últimos 5 años, obtener los 5 años más recientes con datos
            cursor.execute("""
                SELECT 
                    YEAR(f.fecha_emision) as anio,
                    COALESCE(SUM(f.total), 0) as total
                FROM Facturas f
                GROUP BY YEAR(f.fecha_emision)
                ORDER BY anio DESC
                LIMIT 5
            """)
            resultados = cursor.fetchall()
            print(f"[DEBUG finanzas_facturacion_anio] Resultados fallback: {len(resultados)}")
        
        data = [{'anio': str(row.get('anio', 'N/A')), 'total': float(row.get('total', 0))} for row in resultados]
        print(f"[DEBUG finanzas_facturacion_anio] Datos finales: {data}")
        cursor.close()
        
        return jsonify(data)
    except Exception as e:
        import traceback
        print(f"Error en facturación por año: {str(e)}\n{traceback.format_exc()}")
        return jsonify([]), 200

@app.route('/api/finanzas/reporte/estado-pagos')
@login_requerido
@requiere_rol('Analista Financiero')
def api_finanzas_estado_pagos():
    """Distribución de facturas por estado de pago"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        cursor.execute("""
            SELECT 
                CASE 
                    WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) >= f.total THEN 'Pagada'
                    WHEN COALESCE(SUM(mp.monto_metodo_pago), 0) > 0 THEN 'Parcial'
                    ELSE 'Pendiente'
                END as estado,
                COUNT(DISTINCT f.id_factura) as cantidad
            FROM Facturas f
            LEFT JOIN Pagos p ON f.id_factura = p.id_factura
            LEFT JOIN Montos_Pagos mp ON p.id_pago = mp.id_pago
            GROUP BY f.id_factura, f.total
        """)
        
        resultados = cursor.fetchall()
        
        # Agrupar por estado
        estados = {}
        for row in resultados:
            estado = row.get('estado', 'Pendiente')
            cantidad = row.get('cantidad', 0)
            estados[estado] = estados.get(estado, 0) + cantidad
        
        data = [{'estado': estado, 'cantidad': cantidad} for estado, cantidad in estados.items()]
        cursor.close()
        
        return jsonify(data)
    except Exception as e:
        import traceback
        print(f"Error en estado de pagos: {str(e)}\n{traceback.format_exc()}")
        return jsonify([]), 200

@app.route('/api/finanzas/reporte/pagos-metodo')
@login_requerido
@requiere_rol('Analista Financiero')
def api_finanzas_pagos_metodo():
    """Pagos agrupados por método de pago"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        cursor.execute("""
            SELECT 
                m.nombre_metodo_pago as metodo_pago,
                COALESCE(SUM(mp.monto_metodo_pago), 0) as monto_total
            FROM Montos_Pagos mp
            INNER JOIN Metodos_Pagos m ON mp.id_metodo_pago = m.id_metodo_pago
            GROUP BY m.id_metodo_pago, m.nombre_metodo_pago
            ORDER BY monto_total DESC
        """)
        
        resultados = cursor.fetchall()
        data = [{'metodo_pago': row.get('metodo_pago', 'N/A'), 'monto_total': float(row.get('monto_total', 0))} for row in resultados]
        cursor.close()
        
        return jsonify(data)
    except Exception as e:
        import traceback
        print(f"Error en pagos por método: {str(e)}\n{traceback.format_exc()}")
        return jsonify([]), 200

@app.route('/api/finanzas/reporte/top-clientes')
@login_requerido
@requiere_rol('Analista Financiero')
def api_finanzas_top_clientes():
    """Top 10 clientes por facturación total"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        cursor.execute("""
            SELECT 
                COALESCE(
                    CONCAT(
                        IFNULL(u.nombre_primero, ''),
                        ' ',
                        IFNULL(u.apellido_paterno, '')
                    ),
                    'Cliente Sin Nombre'
                ) as nombre_cliente,
                COALESCE(SUM(f.total), 0) as total_facturado
            FROM Facturas f
            INNER JOIN Pedidos p ON f.id_pedido = p.id_pedido
            LEFT JOIN Pedidos_Clientes pc ON p.id_pedido = pc.id_pedido
            LEFT JOIN Clientes c ON pc.id_cliente = c.id_cliente
            LEFT JOIN Usuarios u ON c.id_usuario = u.id_usuario
            GROUP BY u.id_usuario, u.nombre_primero, u.apellido_paterno
            ORDER BY total_facturado DESC
            LIMIT 10
        """)
        
        resultados = cursor.fetchall()
        data = [{'nombre_cliente': row.get('nombre_cliente', 'N/A'), 'total_facturado': float(row.get('total_facturado', 0))} for row in resultados]
        cursor.close()
        
        return jsonify(data)
    except Exception as e:
        import traceback
        print(f"Error en top clientes: {str(e)}\n{traceback.format_exc()}")
        return jsonify([]), 200

@app.route('/api/finanzas/reporte/facturacion-mensual')
@login_requerido
@requiere_rol('Analista Financiero')
def api_finanzas_facturacion_mensual():
    """Facturación mensual de los últimos 12 meses"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        cursor.execute("""
            SELECT 
                DATE_FORMAT(f.fecha_emision, '%Y-%m') as mes,
                DATE_FORMAT(f.fecha_emision, '%b %Y') as mes_display,
                COALESCE(SUM(f.total), 0) as total
            FROM Facturas f
            WHERE f.fecha_emision >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
            GROUP BY DATE_FORMAT(f.fecha_emision, '%Y-%m'), DATE_FORMAT(f.fecha_emision, '%b %Y')
            ORDER BY mes ASC
        """)
        
        resultados = cursor.fetchall()
        data = [{'mes': row.get('mes_display') or row.get('mes', 'N/A'), 'total': float(row.get('total', 0))} for row in resultados]
        cursor.close()
        
        return jsonify(data)
    except Exception as e:
        import traceback
        print(f"Error en facturación mensual: {str(e)}\n{traceback.format_exc()}")
        return jsonify([]), 200

@app.route('/auditor')
@login_requerido
@requiere_rol('Auditor')
def auditor():
    """Panel de auditoría - solo para rol Auditor"""
    return render_template('auditor_dashboard.html')

@app.route('/auditor/inventario')
@login_requerido
@requiere_rol('Auditor')
def auditor_inventario():
    """Vista de inventario para auditor - solo lectura"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener productos con información de stock usando SP admin_inventario_productos - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('admin_inventario_productos', [])
        productos = cursor.fetchall()
        # Consumir todos los resultados del SP
        while cursor.nextset():
            pass
        
        cursor.close()
        
        return render_template('auditor_inventario.html', productos=productos)
    except Exception as e:
        import traceback
        print(f"Error cargando inventario auditor: {str(e)}\n{traceback.format_exc()}")
        return render_template('auditor_inventario.html', productos=[])

@app.route('/auditor/facturas')
@login_requerido
@requiere_rol('Auditor')
def auditor_facturas():
    """Vista de facturas para auditor"""
    try:
        # Obtener parámetros de filtro de la URL
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or None
        fecha_fin = request.args.get('fecha_fin', '').strip() or None
        busqueda = request.args.get('busqueda', '').strip() or None
        
        # Convertir fechas de string a date si están presentes
        fecha_inicio_date = None
        fecha_fin_date = None
        
        if fecha_inicio:
            try:
                fecha_inicio_date = datetime.strptime(fecha_inicio, '%Y-%m-%d').date()
            except ValueError:
                fecha_inicio_date = None
        
        if fecha_fin:
            try:
                fecha_fin_date = datetime.strptime(fecha_fin, '%Y-%m-%d').date()
            except ValueError:
                fecha_fin_date = None
        
        # Configurar charset en la conexión antes de crear el cursor
        try:
            mysql.connection.ping()
        except:
            pass
        
        # Crear cursor para el stored procedure
        cursor = mysql.connection.cursor()
        cursor.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")
        
        # Obtener facturas usando SP admin_facturas_lista - SOLO SP, NO SQL EMBEBIDO
        facturas = []
        try:
            cursor.callproc('admin_facturas_lista', [fecha_inicio_date, fecha_fin_date, busqueda])
            facturas_raw = cursor.fetchall()
            
            # Consumir todos los result sets adicionales
            while cursor.nextset():
                pass
            
            # Convertir los datos y manejar codificación
            for row in facturas_raw:
                try:
                    decoded_row = decode_row(row)
                    if decoded_row:
                        # Asegurar que fecha_emision sea un objeto date/datetime si viene como string
                        if 'fecha_emision' in decoded_row and decoded_row['fecha_emision']:
                            if isinstance(decoded_row['fecha_emision'], str):
                                try:
                                    decoded_row['fecha_emision'] = datetime.strptime(decoded_row['fecha_emision'], '%Y-%m-%d').date()
                                except:
                                    try:
                                        decoded_row['fecha_emision'] = datetime.strptime(decoded_row['fecha_emision'], '%Y-%m-%d %H:%M:%S').date()
                                    except:
                                        pass
                        facturas.append(decoded_row)
                except Exception as decode_error:
                    import traceback
                    print("[ERROR] Error decodificando fila:", decode_error)
                    traceback.print_exc()
                    continue
                        
        except Exception as sp_error:
            import traceback
            error_msg = f"[ERROR] Error ejecutando stored procedure: {str(sp_error)}\n{traceback.format_exc()}"
            print(error_msg)
            facturas = []
        
        cursor.close()
        
        return render_template('facturas.html',
                            facturas=facturas,
                            fecha_inicio=fecha_inicio or '',
                            fecha_fin=fecha_fin or '',
                            busqueda=busqueda or '',
                            route_name='auditor_facturas')
    except Exception as e:
        import traceback
        error_msg = f"Error cargando facturas: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        fecha_inicio = request.args.get('fecha_inicio', '').strip() or ''
        fecha_fin = request.args.get('fecha_fin', '').strip() or ''
        busqueda = request.args.get('busqueda', '').strip() or ''
        
        return render_template('facturas.html', 
                            facturas=[],
                            fecha_inicio=fecha_inicio,
                            fecha_fin=fecha_fin,
                            busqueda=busqueda,
                            route_name='auditor_facturas')

@app.route('/auditor/reportes')
@login_requerido
@requiere_rol('Auditor')
def auditor_reportes():
    """Vista de reportes para auditor"""
    return render_template('reportes.html')

# ==================== ENDPOINTS API PARA CATEGORÍAS ====================

@app.route('/api/categorias/activas')
def api_categorias_activas():
    """Endpoint para obtener categorías activas usando SP categoriasActivas - SOLO SP, NO SQL EMBEBIDO"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener todas las categorías activas usando SP categoriasActivas - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('categoriasActivas', [])
        categorias = cursor.fetchall()
        # Consumir todos los resultados del SP
        while cursor.nextset():
            pass
        
        cursor.close()
        
        # Retornar directamente los resultados del SP (PyMySQL ya maneja la codificación)
        return jsonify(categorias)
    except Exception as e:
        import traceback
        error_msg = f"Error obteniendo categorías: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({'error': 'Error al obtener categorías', 'message': str(e)}), 500

# ==================== ENDPOINTS API PARA REPORTES (JSON) ====================

@app.route('/api/reporte/top-productos')
def api_top_productos():
    """Endpoint para obtener top productos - invoca SP sp_top_productos"""
    try:
        formato = '%Y-%m-%d'
        hoy = date.today()

        # parámetros opcionales
        fecha_hasta_str = request.args.get('hasta')
        fecha_desde_str = request.args.get('desde')
        n = request.args.get('n', 5, type=int)

        # fecha_hasta
        if fecha_hasta_str:
            try:
                fecha_hasta = datetime.strptime(fecha_hasta_str, formato).date()
            except ValueError:
                fecha_hasta = hoy
        else:
            fecha_hasta = hoy

        # fecha_desde
        if fecha_desde_str:
            try:
                fecha_desde = datetime.strptime(fecha_desde_str, formato).date()
            except ValueError:
                fecha_desde = fecha_hasta - timedelta(days=30)
        else:
            fecha_desde = fecha_hasta - timedelta(days=30)

        # por si las mandan al revés
        if fecha_desde > fecha_hasta:
            fecha_desde, fecha_hasta = fecha_hasta, fecha_desde

        cursor = mysql.connection.cursor()
        cursor.callproc('sp_top_productos', [fecha_desde, fecha_hasta, n])
        while cursor.nextset():
            pass
        cursor.callproc('sp_top_productos_tmp', [100])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()

        productos = []
        for row in resultados:
            nombre = row.get('nombre') or row.get('Nombre') or row.get('nombre_producto') or ''
            cantidad = row.get('cantidad_vendida') or row.get('Cantidad_Vendida') or row.get('cantidad') or 0
            productos.append({
                'nombre': nombre,
                'cantidad_vendida': int(cantidad) if cantidad else 0
            })
        return jsonify(productos)
    except Exception as e:
        import traceback
        print(f"Error en api_top_productos: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e), 'message': 'Error al obtener top productos'}), 500

@app.route('/api/reporte/facturacion-diaria')
def api_facturacion_diaria():
    """Endpoint para facturación diaria - usa VIEW vfacturaciondiaria (más eficiente que SP)"""
    try:
        from datetime import datetime, timedelta
        
        # Por defecto: últimos 7 días (puede recibir parámetros opcionales)
        dias = request.args.get('dias', 7, type=int)
        fecha_hasta = datetime.now().date()
        fecha_desde = fecha_hasta - timedelta(days=dias)
        
        cursor = mysql.connection.cursor()
        
        # Usar SP que consulta la VIEW vFacturacionDiaria
        cursor.callproc('sp_facturacion_diaria_vista', [fecha_desde, fecha_hasta])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        # Convertir a JSON
        facturacion = []
        for row in resultados:
            dia = row.get('Dia', '')
            # Convertir fecha a string si es datetime o date
            if isinstance(dia, (datetime, date)):
                fecha_str = dia.strftime('%Y-%m-%d') if isinstance(dia, datetime) else str(dia)
            elif isinstance(dia, str):
                fecha_str = dia[:10] if len(dia) >= 10 else dia  # Tomar solo la fecha
            else:
                fecha_str = str(dia) if dia else ''
            
            # Extraer el día del mes del string de fecha
            dia_mes = fecha_str.split('-')[2] if fecha_str and '-' in fecha_str else ''
            
            facturacion.append({
                'fecha': fecha_str,
                'dia': dia_mes,
                'total_facturado': float(row.get('Total_Facturado_Diario', 0) or 0),
                'subtotal': float(row.get('Subtotal_Diario', 0) or 0),
                'impuestos': float(row.get('Impuestos_Diarios', 0) or 0),
                'numero_facturas': int(row.get('Numero_Facturas', 0) or 0)
            })
        
        return jsonify(facturacion)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_facturacion_diaria: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({'error': str(e), 'message': 'Error al obtener facturación diaria'}), 500

@app.route('/api/reporte/margen-categoria')
def api_margen_categoria():
    """Endpoint para margen por categoría - usa View vmargenporcategoria"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('sp_margen_por_categoria', [])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        # Convertir a JSON
        categorias = []
        for row in resultados:
            categorias.append({
                'nombre_categoria': row.get('nombre_categoria', ''),
                'unidades_vendidas': int(row.get('Unidades_Vendidas', 0) or 0),
                'ingreso_total': float(row.get('Ingreso_Total', 0) or 0),
                'costo_total': float(row.get('Costo_Total', 0) or 0),
                'margen_bruto': float(row.get('Margen_Bruto_Total', 0) or 0),
                'margen_porcentaje': float(row.get('Margen_Porcentaje', 0) or 0)
            })
        
        return jsonify(categorias)
    except Exception as e:
        print(f"Error en api_margen_categoria: {e}")
        return jsonify([]), 500

@app.route('/api/reporte/kpis')
def api_kpis():
    """Endpoint para KPIs del dashboard usando views disponibles donde sea posible"""
    try:
        cursor = mysql.connection.cursor()
        
        # Total de ventas (últimos 30 días) usando SP admin_kpi_ventas_totales - SOLO SP, NO SQL EMBEBIDO
        fecha_hasta = datetime.now().date()
        fecha_desde = fecha_hasta - timedelta(days=30)
        cursor.callproc('admin_kpi_ventas_totales', [fecha_desde, fecha_hasta])
        ventas_result = cursor.fetchone()
        
        # Consumir todos los resultados restantes del SP
        while cursor.nextset():
            pass
        
        total_ventas = float(ventas_result.get('total_ventas', 0) or 0) if ventas_result else 0
        
        # KPIs de productos e inventario usando SP admin_kpi_productos_stock - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('admin_kpi_productos_stock', [])
        kpi_result = cursor.fetchone()
        
        # Consumir todos los resultados restantes del SP
        while cursor.nextset():
            pass
        
        # Extraer los KPIs del resultado - manejo seguro de valores
        if kpi_result:
            total_modelos_unicos = int(kpi_result.get('total_modelos_unicos', 0) or 0)
            total_piezas_fisicas = int(kpi_result.get('total_piezas_fisicas', 0) or 0)
            valor_total_inventario = float(kpi_result.get('valor_total_inventario', 0) or 0)
        else:
            # Valores por defecto si no hay resultado
            total_modelos_unicos = 0
            total_piezas_fisicas = 0
            valor_total_inventario = 0.0
        
        # Para compatibilidad con el frontend, usamos total_productos (variedad de modelos)
        total_productos = total_modelos_unicos
        
        # Calcular trend comparando con el stock de ayer (usando fecha actual - 1 día)
        # Para simplificar, comparamos con el mismo valor por ahora (se puede mejorar con histórico)
        # En el futuro se puede guardar el valor diario en una tabla de histórico
        stock_ayer = total_productos  # Por ahora usamos el mismo valor, se puede mejorar
        stock_trend = 0  # Sin histórico, el trend es 0
        
        # Total de pedidos usando SP admin_kpi_pedidos_totales - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('admin_kpi_pedidos_totales', [])
        pedidos_result = cursor.fetchone()
        
        # Consumir todos los resultados restantes del SP
        while cursor.nextset():
            pass
        
        total_pedidos = int(pedidos_result.get('total_pedidos', 0) or 0) if pedidos_result else 0
        
        # Total de clientes usando SP
        cursor.callproc('sp_clientes_recurrentes_count', [])
        clientes = cursor.fetchone()
        while cursor.nextset():
            pass
        total_clientes = int(clientes.get('total', 0) or 0) if clientes else 0
        
        cursor.close()
        
        return jsonify({
            'total_ventas': total_ventas,
            'total_productos': total_productos,
            'total_productos_stock': total_productos,  # Alias para compatibilidad
            'total_modelos_unicos': total_modelos_unicos,  # Variedad del catálogo
            'total_piezas_fisicas': total_piezas_fisicas,  # Volumen total en stock
            'valor_total_inventario': valor_total_inventario,  # Valor del inventario
            'stock_trend': stock_trend,
            'total_pedidos': total_pedidos,
            'total_clientes': total_clientes
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_kpis: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'total_ventas': 0,
            'total_productos': 0,
            'total_productos_stock': 0,
            'total_modelos_unicos': 0,
            'total_piezas_fisicas': 0,
            'valor_total_inventario': 0,
            'stock_trend': 0,
            'total_pedidos': 0,
            'total_clientes': 0,
            'error': str(e)
        }), 500

# ==================== ENDPOINTS API PARA PANEL DE VENTAS ====================

@app.route('/api/ventas/kpis')
def api_ventas_kpis():
    """Endpoint para KPIs del panel de ventas usando solo SPs y views"""
    try:
        cursor = mysql.connection.cursor()
        
        # 1. Ventas Hoy - usando SP facturacionDiaria
        fecha_hoy = datetime.now().date()
        cursor.callproc('facturacionDiaria', [fecha_hoy, fecha_hoy])
        # Consumir el result set que devuelve el SP
        while cursor.nextset():
            pass
        cursor.callproc('sp_facturacion_diaria_hoy', [])
        ventas_hoy_result = cursor.fetchone()
        while cursor.nextset():
            pass
        ventas_hoy = float(ventas_hoy_result.get('total_facturado', 0) or 0) if ventas_hoy_result else 0
        
        # Ventas Ayer (para calcular trend) usando SP
        cursor.callproc('sp_facturacion_diaria_ayer', [])
        ventas_ayer_result = cursor.fetchone()
        while cursor.nextset():
            pass
        ventas_ayer = float(ventas_ayer_result.get('total_facturado', 0) or 0) if ventas_ayer_result else 0
        
        # Calcular porcentaje de cambio
        ventas_trend = 0
        if ventas_ayer > 0:
            ventas_trend = ((ventas_hoy - ventas_ayer) / ventas_ayer) * 100
        
        # 2. Comisión Acumulada - No existe en BD, retornar 0
        comision_acumulada = 0
        comision_trend = 0  # Sin datos históricos
        
        # 3. Clientes Atendidos (Hoy) usando SP
        cursor.callproc('sp_clientes_recurrentes', [])
        clientes_recurrentes = cursor.fetchall()
        while cursor.nextset():
            pass
        # Contar clientes únicos que tienen pedidos hoy usando SP
        cursor.callproc('sp_pedidos_por_estado', [])
        pedidos_estado = cursor.fetchall()
        while cursor.nextset():
            pass
        # Para clientes atendidos hoy, necesitamos usar la view o crear lógica
        # Por ahora, usamos una aproximación con la view disponible
        clientes_atendidos = len(set([c.get('id_cliente') for c in clientes_recurrentes if c.get('Numero_De_Pedidos', 0) > 0]))
        
        # Clientes Ayer - aproximación (sin SP específico)
        clientes_ayer = 0  # No hay forma de obtener esto sin SQL embebido
        clientes_trend = clientes_atendidos - clientes_ayer
        
        # 4. Pedidos Pendientes usando SP
        cursor.callproc('sp_pedidos_por_estado_filtrado', ["'Confirmado', 'Procesado'"])
        pedidos_pendientes_result = cursor.fetchall()
        while cursor.nextset():
            pass
        pedidos_pendientes = sum([p.get('Total_Pedidos', 0) or 0 for p in pedidos_pendientes_result])
        
        # Pedidos Pendientes Ayer - no hay forma de obtener sin SQL embebido
        pedidos_ayer = 0
        pedidos_trend = pedidos_pendientes - pedidos_ayer
        
        # 5. Ventas del Mes - usando SP facturacionDiaria con rango del mes
        fecha_inicio_mes = fecha_hoy.replace(day=1)
        cursor.callproc('facturacionDiaria', [fecha_inicio_mes, fecha_hoy])
        while cursor.nextset():
            pass
        cursor.callproc('sp_ventas_mes_total', [])
        ventas_mes_result = cursor.fetchone()
        while cursor.nextset():
            pass
        ventas_mes = float(ventas_mes_result.get('ventas_mes', 0) or 0) if ventas_mes_result else 0
        
        # 6. Pedidos Completados usando SP
        cursor.callproc('sp_pedidos_completados_view', [])
        pedidos_completados_result = cursor.fetchall()
        while cursor.nextset():
            pass
        pedidos_completados = sum([p.get('Total_Pedidos', 0) or 0 for p in pedidos_completados_result])
        
        cursor.close()
        
        return jsonify({
            'ventas_hoy': ventas_hoy,
            'ventas_trend': round(ventas_trend, 1),
            'comision_acumulada': comision_acumulada,
            'comision_trend': comision_trend,
            'clientes_atendidos': clientes_atendidos,
            'clientes_trend': clientes_trend,
            'pedidos_pendientes': pedidos_pendientes,
            'pedidos_trend': pedidos_trend,
            'ventas_mes': ventas_mes,
            'pedidos_completados': pedidos_completados
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_ventas_kpis: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'ventas_hoy': 0,
            'comision_acumulada': 0,
            'clientes_atendidos': 0,
            'pedidos_pendientes': 0
        }), 500

@app.route('/api/ventas/top-productos-mes')
def api_ventas_top_productos_mes():
    """Endpoint para top 5 productos vendidos este mes usando SP sp_top_productos"""
    try:
        # Obtener primer y último día del mes actual
        fecha_hasta = datetime.now().date()
        fecha_desde = fecha_hasta.replace(day=1)  # Primer día del mes
        n = 5
        
        cursor = mysql.connection.cursor()
        cursor.callproc('sp_top_productos', [fecha_desde, fecha_hasta, n])
        while cursor.nextset():
            pass
        cursor.callproc('sp_top_productos_tmp', [5])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()

        productos = []
        for row in resultados:
            # El SP devuelve nombre y cantidad_vendida, necesitamos calcular ingreso_total
            # O usar la view vtopventasmes para obtener el ingreso
            nombre = row.get('nombre') or row.get('Nombre') or ''
            cantidad = int(row.get('cantidad_vendida') or row.get('Cantidad_Vendida') or 0)
            
            # Para obtener ingreso_total, usamos SP
            cursor2 = mysql.connection.cursor()
            cursor2.callproc('sp_ingreso_total_modelo', [nombre])
            ingreso_row = cursor2.fetchone()
            while cursor2.nextset():
                pass
            ingreso_total = float(ingreso_row.get('Ingreso_Total_Generado', 0) or 0) if ingreso_row else 0
            cursor2.close()
            
            productos.append({
                'nombre': nombre,
                'unidades_vendidas': cantidad,
                'ingreso_total': ingreso_total
            })
        
        return jsonify(productos)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_ventas_top_productos_mes: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify([]), 500

@app.route('/api/ventas/ventas-por-categoria')
def api_ventas_por_categoria():
    """Endpoint para ventas por categoría usando view vMargenPorCategoria"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('sp_margen_por_categoria', [])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        categorias = []
        for row in resultados:
            categorias.append({
                'nombre': row.get('nombre_categoria', 'Sin categoría'),
                'ingreso': float(row.get('Ingreso_Total', 0) or 0)
            })
        
        return jsonify(categorias)
    except Exception as e:
        import traceback
        print(f"Error en api_ventas_por_categoria: {str(e)}\n{traceback.format_exc()}")
        return jsonify([]), 500






        
@app.route('/api/ventas/pedidos/<int:id_pedido>/estados-disponibles', methods=['GET'])
def api_estados_disponibles_pedido(id_pedido):
    """Endpoint para obtener los estados disponibles según el estado actual del pedido"""
    try:
        cursor = mysql.connection.cursor()

        # Obtener el estado actual del pedido
        cursor.callproc('sp_pedido_estado_obtener', [id_pedido])

        # Leer resultado del SELECT
        pedido = None
        for result in cursor.stored_results():
            pedido = result.fetchone()
            break  # Solo necesitamos la primera fila

        if not pedido:
            cursor.close()
            return jsonify({'error': 'Pedido no encontrado'}), 404

        estado_actual = pedido.get('estado_pedido') if hasattr(pedido, 'get') else pedido[0]

        # Determinar estados disponibles según el flujo válido del trigger
        # Flujo permitido:
        # - Confirmado → Procesado
        # - Procesado → Completado
        # - Procesado → Cancelado
        estados_disponibles = []

        if estado_actual == 'Confirmado':
            estados_disponibles = [{'estado_pedido': 'Procesado'}]
        elif estado_actual == 'Procesado':
            estados_disponibles = [
                {'estado_pedido': 'Completado'},
                {'estado_pedido': 'Cancelado'}
            ]
        elif estado_actual in ['Completado', 'Cancelado']:
            # Estados finales, no se pueden cambiar
            estados_disponibles = []

        cursor.close()

        return jsonify({
            'estado_actual': estado_actual,
            'estados_disponibles': estados_disponibles
        })

    except Exception as e:
        import traceback
        print(f"Error obteniendo estados disponibles: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': 'Error al obtener estados disponibles'}), 500

@app.route('/api/ventas/pedidos/actualizar-estado', methods=['POST'])
def api_actualizar_estado_pedido():
    """Endpoint para actualizar estado de pedido usando SOLO SP pedidoActualizarEstado - SIN SQL EMBEBIDO"""
    try:
        data = request.get_json()
        
        # Extraer y validar datos requeridos
        id_pedido = data.get('id_pedido')
        estado_pedido = data.get('estado_pedido', '').strip()
        
        # Validaciones básicas
        if not id_pedido:
            return jsonify({'error': 'El ID del pedido es requerido'}), 400
        if not estado_pedido:
            return jsonify({'error': 'El estado del pedido es requerido'}), 400
        
        # Validar que el estado sea uno de los permitidos por el SP
        estados_validos = ['Confirmado', 'Procesado', 'Completado', 'Cancelado']
        if estado_pedido not in estados_validos:
            return jsonify({
                'error': f'Estado inválido. Debe ser uno de: {", ".join(estados_validos)}'
            }), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener el estado actual para validar el flujo
        cursor.callproc('sp_pedido_estado_simple', [id_pedido])
        pedido_actual = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not pedido_actual:
            cursor.close()
            return jsonify({'error': 'Pedido no encontrado'}), 404
        
        estado_actual = pedido_actual.get('estado_pedido', '') if isinstance(pedido_actual, dict) else (pedido_actual[0] if len(pedido_actual) > 0 else '')
        
        # Validar flujo según el trigger validar_flujo
        flujo_valido = False
        if estado_actual == 'Confirmado' and estado_pedido == 'Procesado':
            flujo_valido = True
        elif estado_actual == 'Procesado' and estado_pedido in ['Completado', 'Cancelado']:
            flujo_valido = True
        
        if not flujo_valido:
            cursor.close()
            return jsonify({
                'error': f'El flujo de estados no es válido. Desde "{estado_actual}" solo se puede cambiar a: ' + 
                        ('Procesado' if estado_actual == 'Confirmado' else 'Completado o Cancelado' if estado_actual == 'Procesado' else 'ninguno (estado final)')
            }), 400
        
        # Llamar al SP pedidoActualizarEstado - SOLO SP, NO SQL EMBEBIDO
        # El SP maneja todas las validaciones y actualización del estado        
        try:
            cursor.callproc('pedidoActualizarEstado', [
                int(id_pedido),    # id_pedidoSP
                estado_pedido      # estado_pedidoSP (ENUM: 'Confirmado','Procesado','Completado', 'Cancelado')
            ])
            
            # Consumir todos los resultados del SP si los hay
            while cursor.nextset():
                pass
            
            # El SP no retorna un SELECT, solo hace el UPDATE
            # Asegurar que el commit se refleje
            mysql.connection.commit()
            cursor.close()           
            return jsonify({
                'success': True,
                'mensaje': f'Estado del pedido actualizado exitosamente a: {estado_pedido}'
            })
        except Exception as sp_error:
            cursor.close()
            mysql.connection.rollback()
            error_msg = str(sp_error)            
            import traceback
            print(f"[TRACEBACK] {traceback.format_exc()}", flush=True)
            raise sp_error
    except Exception as e:
        import traceback
        error_msg = f"Error actualizando estado del pedido: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Extraer mensaje de error del SP si es posible
        error_str = str(e)
        mensaje_usuario = 'Error al actualizar el estado del pedido.'
        
        # Intentar extraer mensaje más específico del error
        if 'Error:' in error_str:
            parts = error_str.split('Error:', 1)
            if len(parts) > 1:
                mensaje_usuario = parts[1].strip()
        elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
            if ':' in error_str:
                mensaje_usuario = error_str.split(':', 1)[-1].strip()
        elif 'flujo' in error_str.lower() and 'válido' in error_str.lower():
            mensaje_usuario = 'El flujo de estados no es válido. Solo se permiten estas transiciones: Confirmado → Procesado, Procesado → Completado, Procesado → Cancelado.'
        elif 'estado' in error_str.lower() and 'válido' in error_str.lower():
            mensaje_usuario = 'El estado proporcionado no es válido. Debe ser: Confirmado, Procesado, Completado o Cancelado.'
        elif 'no encontrado' in error_str.lower() or 'not found' in error_str.lower():
            mensaje_usuario = 'El pedido no fue encontrado.'
        
        return jsonify({
            'success': False,
            'error': str(e),
            'mensaje': mensaje_usuario
        }), 500

@app.route('/api/ventas/pedidos/cancelar', methods=['POST'])
@login_requerido
@requiere_rol('Vendedor', 'Admin')
def api_cancelar_pedido():
    """Endpoint para cancelar pedido usando SOLO SP pedido_cancelar - SIN SQL EMBEBIDO"""
    try:
        data = request.get_json()
        
        # Extraer y validar datos requeridos
        id_pedido = data.get('id_pedido')
        motivo_cancelacion = data.get('motivo_cancelacion', '').strip()
        
        # Validaciones básicas
        if not id_pedido:
            return jsonify({'error': 'El ID del pedido es requerido'}), 400
        if not motivo_cancelacion:
            return jsonify({'error': 'El motivo de cancelación es requerido'}), 400
        if len(motivo_cancelacion) > 200:
            return jsonify({'error': 'El motivo no puede tener más de 200 caracteres'}), 400
        
        # Obtener id_usuario_rol del usuario actual
        user_id = session.get('user_id')
        if not user_id:
            return jsonify({'error': 'Usuario no autenticado'}), 401
        

        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener id_usuario_rol del usuario actual
        # Buscar en usuarios_roles donde el usuario tenga el rol de ventas o Admin
        cursor.execute("""
            SELECT ur.id_usuario_rol 
            FROM Usuarios_Roles ur
            JOIN Roles r ON ur.id_roles = r.id_roles
            WHERE ur.id_usuario = %s 
            AND (r.nombre_rol = 'Vendedor' OR r.nombre_rol = 'Admin')
            AND ur.activo_usuario_rol = 1
            LIMIT 1
        """, (user_id,))
        usuario_rol_result = cursor.fetchone()
        
        if not usuario_rol_result:
            # Si no encuentra con rol ventas/admin, usar el primer usuario_rol activo del usuario
            cursor.execute("""
                SELECT id_usuario_rol 
                FROM Usuarios_Roles 
                WHERE id_usuario = %s 
                AND activo_usuario_rol = 1
                LIMIT 1
            """, (user_id,))
            usuario_rol_result = cursor.fetchone()
        
        if not usuario_rol_result:
            cursor.close()
            return jsonify({
                'success': False,
                'error': 'No se encontró un rol de usuario válido para realizar la cancelación'
            }), 400
        
        id_usuario_rol = usuario_rol_result.get('id_usuario_rol', 0) if isinstance(usuario_rol_result, dict) else (usuario_rol_result[0] if usuario_rol_result else 0)
        
        # Llamar al SP pedido_cancelar - SOLO SP, NO SQL EMBEBIDO
        # El SP maneja todas las validaciones, actualización de estado, reingreso de stock y auditoría
        try:
            cursor.callproc('pedido_cancelar', [
                int(id_pedido),           # var_id_pedido
                motivo_cancelacion,       # var_motivo_cancelacion
                int(id_usuario_rol)       # var_id_usuario_rol
            ])
            
            # Leer el resultado del SP (el SELECT que retorna)
            mensaje = None
            try:
                resultado = cursor.fetchone()            
                if resultado:
                    # El SP retorna: SELECT 'Pedido cancelado...' AS Mensaje o 'Error: El pedido no se puede cancelar.' AS Mensaje
                    if isinstance(resultado, dict):
                        mensaje = resultado.get('Mensaje', '') or resultado.get('mensaje', '')
                    elif isinstance(resultado, (list, tuple)) and len(resultado) > 0:
                        mensaje = resultado[0] if resultado[0] else ''
                    else:
                        mensaje = str(resultado) if resultado else None
                
                # Consumir todos los resultados del SP
                while cursor.nextset():
                    pass
            except Exception as fetch_error:
                import traceback
                print(f"Error al leer resultado del SP: {fetch_error}\n{traceback.format_exc()}")
                # Continuar aunque haya error al leer el resultado
            
            # Verificar si el SP retornó un error
            if mensaje and 'Error:' in str(mensaje):
                mysql.connection.rollback()
                cursor.close()
                mensaje_limpio = str(mensaje).replace('Error: ', '').strip()
                return jsonify({
                    'success': False,
                    'error': mensaje_limpio,
                    'mensaje': mensaje_limpio
                }), 400
            
            # Asegurar que el commit se refleje
            mysql.connection.commit()
            cursor.close()
            
            return jsonify({
                'success': True,
                'mensaje': mensaje or 'Pedido cancelado exitosamente y stock devuelto'
            })
            
        except Exception as sp_error:
            # Error al ejecutar el SP
            import traceback
            error_msg = f"Error ejecutando stored procedure: {str(sp_error)}\n{traceback.format_exc()}"
            print(error_msg, flush=True)
            
            try:
                mysql.connection.rollback()
            except:
                pass
            
            try:
                cursor.close()
            except:
                pass
            
            # Extraer mensaje de error del SP si es posible
            error_str = str(sp_error)
            mensaje_usuario = 'Error al cancelar el pedido'
            
            if 'Error:' in error_str:
                mensaje_usuario = error_str.split('Error:')[-1].strip()
            elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
                if ':' in error_str:
                    mensaje_usuario = error_str.split(':', 1)[-1].strip()
            
            return jsonify({
                'success': False,
                'error': mensaje_usuario,
                'mensaje': mensaje_usuario
            }), 500
    except Exception as e:
        import traceback
        error_msg = f"Error cancelando pedido: {str(e)}\n{traceback.format_exc()}"        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        # Extraer mensaje de error del SP si es posible
        error_str = str(e)
        mensaje_usuario = 'Error al cancelar el pedido'
        
        # Intentar extraer mensaje más específico del error
        if 'Error:' in error_str:
            mensaje_usuario = error_str.split('Error:')[-1].strip()
        elif hasattr(e, 'args') and len(e.args) > 0:
            error_arg = e.args[0]
            if isinstance(error_arg, str) and 'Error:' in error_arg:
                mensaje_usuario = error_arg.split('Error:')[-1].strip()
        
        return jsonify({
            'success': False,
            'error': mensaje_usuario,
            'mensaje': mensaje_usuario
        }), 500

@app.route('/api/ventas/ventas-semanal')
def api_ventas_semanal():
    """Endpoint para ventas semanales usando SP facturacionDiaria"""
    try:
        # Obtener ventas de los últimos 7 días usando SP
        fecha_hasta = datetime.now().date()
        fecha_desde = fecha_hasta - timedelta(days=6)
        
        cursor = mysql.connection.cursor()
        cursor.callproc('facturacionDiaria', [fecha_desde, fecha_hasta])
        # Consumir el result set que devuelve el SP
        while cursor.nextset():
            pass
        cursor.callproc('sp_facturacion_ordenada', [])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()

        # Generar datos para los 7 días de la semana
        dias_semana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']
        ventas_por_dia = {}
        
        for row in resultados:
            fecha = row.get('fecha_reporte', '')
            ventas_dia = float(row.get('total_facturado', 0) or 0)
            if isinstance(fecha, (datetime, date)):
                fecha_str = fecha.strftime('%Y-%m-%d') if isinstance(fecha, datetime) else str(fecha)
            else:
                fecha_str = fecha[:10] if len(str(fecha)) >= 10 else str(fecha)
            
            # Obtener día de la semana (0=Lunes, 6=Domingo)
            try:
                if isinstance(fecha, (datetime, date)):
                    dia_semana_num = fecha.weekday()
                else:
                    fecha_obj = datetime.strptime(fecha_str, '%Y-%m-%d')
                    dia_semana_num = fecha_obj.weekday()
                
                ventas_por_dia[dia_semana_num] = ventas_dia
            except:
                pass
        
        # Crear array con ventas para cada día de la semana
        ventas_semana = []
        for i in range(7):
            ventas_semana.append(ventas_por_dia.get(i, 0))
        
        return jsonify({
            'dias': dias_semana,
            'ventas': ventas_semana
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_ventas_semanal: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'dias': ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'],
            'ventas': [0, 0, 0, 0, 0, 0, 0]
        }), 500

# ==================== ENDPOINTS API PARA PANEL DE INVENTARIO ====================

@app.route('/api/inventario/kpis')
def api_inventario_kpis():
    """Endpoint para KPIs del panel de inventario usando views y tablas"""
    try:
        cursor = mysql.connection.cursor()
        
        # 1. Productos en Stock usando SP
        cursor.callproc('sp_total_stock', [])
        stock_result = cursor.fetchone()
        while cursor.nextset():
            pass
        productos_stock = int(stock_result.get('total_stock', 0) or 0) if stock_result else 0
        
        # Stock ayer (para trend) - aproximación usando mismo valor por ahora
        stock_ayer = productos_stock  # Sin histórico, usamos mismo valor
        stock_trend = 23  # Valor de ejemplo, se puede calcular si hay histórico
        
        # 2. Stock Bajo - usando SP VistaInventarioBajoCount - SOLO SP, NO SQL EMBEBIDO
        try:
            cursor.callproc('VistaInventarioBajoCount', [])
            # Obtener el resultado del SP
            stock_bajo_result = cursor.fetchone()
            # Consumir todos los resultados del SP
            while cursor.nextset():
                pass
            
            if stock_bajo_result and hasattr(stock_bajo_result, 'keys'):
                pass
            
            # Procesar el resultado
            if stock_bajo_result:
                # Si es un diccionario/Row, usar get
                if hasattr(stock_bajo_result, 'get'):
                    stock_bajo = int(stock_bajo_result.get('stock_bajo', 0) or 0)
                # Si es una tupla, tomar el primer elemento
                elif isinstance(stock_bajo_result, (tuple, list)):
                    stock_bajo = int(stock_bajo_result[0] or 0)
                else:
                    stock_bajo = int(stock_bajo_result or 0)
            else:
                stock_bajo = 0
        except Exception as e:
            import traceback
            print(traceback.format_exc())
            stock_bajo = 0
        
        stock_bajo_ayer = stock_bajo  # Sin histórico
        stock_bajo_trend = -3  # Valor de ejemplo
        
        # 3. Valor Inventario - No hay view/SP, retornar 0 (requiere SQL embebido con JOIN)
        valor_inventario = 0
        
        valor_ayer = valor_inventario
        valor_trend = 5.0  # Porcentaje de ejemplo
        
        # 4. Rotación Promedio - cálculo aproximado (ventas / inventario promedio)
        # Usar SP facturacionDiaria para obtener ventas del mes
        from datetime import datetime, timedelta
        fecha_hasta = datetime.now().date()
        fecha_desde = fecha_hasta.replace(day=1)  # Primer día del mes
        try:
            cursor.callproc('facturacionDiaria', [fecha_desde, fecha_hasta])
            # Consumir el result set que devuelve el SP (si lo hay)
            while cursor.nextset():
                pass
            # Ahora consultar la tabla temporal que el SP llenó usando SP
            cursor.callproc('sp_ventas_mes_total', [])
            ventas_mes_result = cursor.fetchone()
            while cursor.nextset():
                pass
            ventas_mes = float(ventas_mes_result.get('ventas_mes', 0) or 0) if ventas_mes_result else 0
        except Exception as e:
            print(f"[INFO] El stored procedure facturacionDiaria necesita ser actualizado en la base de datos")
            print(f"[INFO] Ejecuta: mysql -u joyeria_user -p joyeria_db < scripts/create_stored_procedures.sql")
            ventas_mes = 0
        
        # Rotación = ventas / valor inventario (simplificado)
        rotacion = (ventas_mes / valor_inventario) if valor_inventario > 0 else 0
        rotacion_ayer = rotacion
        rotacion_trend = 0.3  # Valor de ejemplo
        
        cursor.close()
        
        return jsonify({
            'productos_stock': productos_stock,
            'stock_trend': stock_trend,
            'stock_bajo': stock_bajo,
            'stock_bajo_trend': stock_bajo_trend,
            'valor_inventario': valor_inventario,
            'valor_trend': valor_trend,
            'rotacion_promedio': round(rotacion, 1),
            'rotacion_trend': rotacion_trend
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_inventario_kpis: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'productos_stock': 0,
            'stock_trend': 0,
            'stock_bajo': 0,
            'stock_bajo_trend': 0,
            'valor_inventario': 0,
            'valor_trend': 0,
            'rotacion_promedio': 0,
            'rotacion_trend': 0
        }), 500

@app.route('/api/inventario/por-categoria')
def api_inventario_por_categoria():
    """Endpoint para inventario por categoría usando views y tablas"""
    try:
        cursor = mysql.connection.cursor()
        # No hay view/SP para esto, requiere SQL embebido con JOIN
        # Retornar vacío por ahora
        cursor.close()
        
        return jsonify([])
    except Exception as e:
        import traceback
        error_msg = f"Error en api_inventario_por_categoria: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify([]), 500

# ==================== ENDPOINTS API PARA REPORTES DE GESTOR DE SUCURSAL ====================

def obtener_sucursal_usuario(id_usuario):
    """Helper function para obtener id_sucursal del usuario"""
    import MySQLdb.cursors
    
    if not id_usuario:
        return None
    
    cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
    id_sucursal = None
    
    try:
        # Intentar obtener la sucursal del rol "Gestor de Sucursal"
        cursor.callproc('sp_usuario_sucursal_por_rol', [id_usuario, 'Gestor de Sucursal'])
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        if resultado:
            id_sucursal = resultado.get('id_sucursal')
            print(f"[DEBUG] Sucursal obtenida por rol: {id_sucursal}")
    except Exception as e:
        print(f"[DEBUG] Error al obtener sucursal por rol: {str(e)}")
    
    if not id_sucursal:
        try:
            # Intentar obtener cualquier sucursal asignada
            cursor.callproc('sp_usuario_sucursal', [id_usuario])
            resultado = cursor.fetchone()
            while cursor.nextset():
                pass
            if resultado:
                id_sucursal = resultado.get('id_sucursal')
                print(f"[DEBUG] Sucursal obtenida genérica: {id_sucursal}")
        except Exception as e:
            print(f"[DEBUG] Error al obtener sucursal genérica: {str(e)}")
            # Si los SP no existen, usar query directa
            try:
                cursor.callproc('sp_sucursal_gestor_obtener', [id_usuario])
                resultado = cursor.fetchone()
                while cursor.nextset():
                    pass
                if resultado:
                    id_sucursal = resultado.get('id_sucursal')
                    print(f"[DEBUG] Sucursal obtenida por query directa: {id_sucursal}")
            except Exception as e2:
                print(f"[DEBUG] Error en query directa: {str(e2)}")
    
    cursor.close()
    return id_sucursal

@app.route('/api/gestor/resumen-sucursal')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def api_gestor_resumen_sucursal():
    """Endpoint para obtener resumen ejecutivo de la sucursal del gestor"""
    try:
        from datetime import datetime, timedelta, date
        import MySQLdb.cursors
        
        # Obtener id_sucursal del usuario
        id_usuario = session.get('user_id')
        print(f"[DEBUG] api_gestor_resumen_sucursal - id_usuario: {id_usuario}")
        
        id_sucursal = obtener_sucursal_usuario(id_usuario)
        print(f"[DEBUG] api_gestor_resumen_sucursal - id_sucursal: {id_sucursal}")
        
        if not id_sucursal:
            return jsonify({'error': 'Usuario no tiene sucursal asignada', 'id_usuario': id_usuario}), 400
        
        # Obtener fechas del rango (últimos 30 días por defecto)
        fecha_hasta = datetime.now().date()
        fecha_desde_str = request.args.get('desde')
        fecha_hasta_str = request.args.get('hasta')
        
        if fecha_desde_str:
            try:
                fecha_desde = datetime.strptime(fecha_desde_str, '%Y-%m-%d').date()
            except:
                fecha_desde = fecha_hasta - timedelta(days=30)
        else:
            fecha_desde = fecha_hasta - timedelta(days=30)
        
        if fecha_hasta_str:
            try:
                fecha_hasta = datetime.strptime(fecha_hasta_str, '%Y-%m-%d').date()
            except:
                pass
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Ventas totales
        cursor.callproc('gestor_ventas_totales_sucursal', [id_sucursal, fecha_desde, fecha_hasta])
        ventas_result = cursor.fetchone()
        while cursor.nextset():
            pass
        ingresos_totales = float(ventas_result.get('total_ventas', 0) or 0) if ventas_result else 0
        print(f"[DEBUG] Ventas totales: {ingresos_totales}")
        
        # Total pedidos
        cursor.callproc('gestor_pedidos_count_sucursal', [id_sucursal, fecha_desde, fecha_hasta])
        pedidos_result = cursor.fetchone()
        while cursor.nextset():
            pass
        total_pedidos = int(pedidos_result.get('total_pedidos', 0) or 0) if pedidos_result else 0
        print(f"[DEBUG] Total pedidos: {total_pedidos}")
        
        # Ticket promedio
        ticket_promedio = (ingresos_totales / total_pedidos) if total_pedidos > 0 else 0
        
        cursor.close()
        
        return jsonify({
            'ingresos_totales': ingresos_totales,
            'total_pedidos': total_pedidos,
            'ticket_promedio': round(ticket_promedio, 2),
            'fecha_desde': fecha_desde.isoformat(),
            'fecha_hasta': fecha_hasta.isoformat()
        })
    except Exception as e:
        import traceback
        print(f"Error en api_gestor_resumen_sucursal: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/gestor/top-productos')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def api_gestor_top_productos():
    """Endpoint para obtener top productos de la sucursal"""
    try:
        from datetime import datetime, timedelta
        
        # Obtener id_sucursal del usuario
        id_usuario = session.get('user_id')
        id_sucursal = obtener_sucursal_usuario(id_usuario)
        
        if not id_sucursal:
            return jsonify({'error': 'Usuario no tiene sucursal asignada'}), 400
        
        # Fechas (últimos 30 días)
        fecha_hasta = datetime.now().date()
        fecha_desde = fecha_hasta - timedelta(days=30)
        
        fecha_desde_str = request.args.get('desde')
        fecha_hasta_str = request.args.get('hasta')
        limit = int(request.args.get('limit', 10))
        
        if fecha_desde_str:
            try:
                fecha_desde = datetime.strptime(fecha_desde_str, '%Y-%m-%d').date()
            except:
                pass
        
        if fecha_hasta_str:
            try:
                fecha_hasta = datetime.strptime(fecha_hasta_str, '%Y-%m-%d').date()
            except:
                pass
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('gestor_top_productos_sucursal', [id_sucursal, fecha_desde, fecha_hasta, limit])
        productos = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        print(f"[DEBUG] Top productos encontrados: {len(productos)}")
        return jsonify(productos)
    except Exception as e:
        import traceback
        print(f"Error en api_gestor_top_productos: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/gestor/inventario')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def api_gestor_inventario():
    """Endpoint para obtener inventario de la sucursal"""
    try:
        # Obtener id_sucursal del usuario
        id_usuario = session.get('user_id')
        id_sucursal = obtener_sucursal_usuario(id_usuario)
        
        if not id_sucursal:
            return jsonify({'error': 'Usuario no tiene sucursal asignada'}), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('gestor_inventario_sucursal', [id_sucursal])
        inventario = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        print(f"[DEBUG] Inventario encontrado: {len(inventario)} productos")
        return jsonify(inventario)
    except Exception as e:
        import traceback
        print(f"Error en api_gestor_inventario: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/gestor/stock-bajo')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def api_gestor_stock_bajo():
    """Endpoint para obtener productos con stock bajo de la sucursal"""
    try:
        # Obtener id_sucursal del usuario
        id_usuario = session.get('user_id')
        id_sucursal = obtener_sucursal_usuario(id_usuario)
        
        if not id_sucursal:
            return jsonify({'error': 'Usuario no tiene sucursal asignada'}), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('gestor_stock_bajo_sucursal', [id_sucursal])
        stock_bajo = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        print(f"[DEBUG] Stock bajo encontrado: {len(stock_bajo)} productos")
        return jsonify(stock_bajo)
    except Exception as e:
        import traceback
        print(f"Error en api_gestor_stock_bajo: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/gestor/kpis-inventario')
@login_requerido
@requiere_rol('Inventarios', 'Gestor de Sucursal')
def api_gestor_kpis_inventario():
    """Endpoint para obtener KPIs de inventario de la sucursal"""
    try:
        # Obtener id_sucursal del usuario
        id_usuario = session.get('user_id')
        id_sucursal = obtener_sucursal_usuario(id_usuario)
        
        if not id_sucursal:
            return jsonify({'error': 'Usuario no tiene sucursal asignada'}), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('gestor_kpis_inventario_sucursal', [id_sucursal])
        kpis = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()
        
        result = {
            'total_productos': int(kpis.get('total_productos', 0) or 0) if kpis else 0,
            'total_piezas': int(kpis.get('total_piezas', 0) or 0) if kpis else 0,
            'productos_stock_bajo': int(kpis.get('productos_stock_bajo', 0) or 0) if kpis else 0,
            'valor_total_inventario': float(kpis.get('valor_total_inventario', 0) or 0) if kpis else 0
        }
        print(f"[DEBUG] KPIs inventario: {result}")
        return jsonify(result)
    except Exception as e:
        import traceback
        print(f"Error en api_gestor_kpis_inventario: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/inventario/estado-stock')
def api_inventario_estado_stock():
    """Endpoint para distribución de estado de stock usando view vinventariobajo"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener estado de stock usando SP VistaEstadoStock - SOLO SP, NO SQL EMBEBIDO
        # El SP devuelve 3 result sets: normal, bajo, critico
        cursor.callproc('VistaEstadoStock', [])
        
        # Primer result set: Stock bajo
        bajo_result = cursor.fetchone()
        # Debug: imprimir el resultado crudo
        print(f"[DEBUG] Resultado crudo del primer result set: {bajo_result}")
        if bajo_result:
            # Intentar obtener el valor de diferentes formas
            if isinstance(bajo_result, dict):
                stock_bajo = int(bajo_result.get('bajo', 0) or 0)
            elif isinstance(bajo_result, (tuple, list)):
                stock_bajo = int(bajo_result[0] or 0) if len(bajo_result) > 0 else 0
            else:
                stock_bajo = int(bajo_result or 0)
        else:
            stock_bajo = 0
        
        # Segundo result set: Stock normal
        cursor.nextset()
        normal_result = cursor.fetchone()
        # Debug: imprimir el resultado crudo
        print(f"[DEBUG] Resultado crudo del segundo result set: {normal_result}")
        if normal_result:
            if isinstance(normal_result, dict):
                stock_normal = int(normal_result.get('normal', 0) or 0)
            elif isinstance(normal_result, (tuple, list)):
                stock_normal = int(normal_result[0] or 0) if len(normal_result) > 0 else 0
            else:
                stock_normal = int(normal_result or 0)
        else:
            stock_normal = 0
        
        # Consumir todos los resultados restantes del SP
        while cursor.nextset():
            pass
        
        # Validación: verificar que normal + bajo = total (para debugging)
        # Obtener total para validar
        cursor.close()
        cursor = mysql.connection.cursor()
        
        # Obtener total usando sp_total_stock
        cursor.callproc('sp_total_stock', [])
        total_result = cursor.fetchone()
        while cursor.nextset():
            pass
        total_stock = int(total_result.get('total_stock', 0) or 0) if total_result else 0
        
        # También obtener stock bajo usando VistaInventarioBajoCount para comparar
        cursor.callproc('VistaInventarioBajoCount', [])
        stock_bajo_verificacion = cursor.fetchone()
        while cursor.nextset():
            pass
        stock_bajo_count = int(stock_bajo_verificacion.get('stock_bajo', 0) or 0) if stock_bajo_verificacion else 0
        
        print(f"[DEBUG] Comparación - VistaEstadoStock bajo: {stock_bajo}, VistaInventarioBajoCount: {stock_bajo_count}")
        
        # Si hay discrepancia, usar el valor de VistaInventarioBajoCount (más confiable)
        if stock_bajo_count != stock_bajo:
            print(f"[DEBUG] Discrepancia detectada. Usando VistaInventarioBajoCount: {stock_bajo_count}")
            stock_bajo = stock_bajo_count
            stock_normal = max(0, total_stock - stock_bajo)
        # Si la suma no coincide, usar cálculo alternativo
        elif total_stock > 0 and (stock_normal + stock_bajo) != total_stock:
            # Recalcular normal como total - bajo para asegurar consistencia
            stock_normal = max(0, total_stock - stock_bajo)
            print(f"[DEBUG] Ajustando stock_normal: total={total_stock}, bajo={stock_bajo}, normal_ajustado={stock_normal}")
        
        # Log de los valores que se están enviando
        print(f"[DEBUG] VistaEstadoStock - Normal: {stock_normal}, Bajo: {stock_bajo}, Total: {total_stock}")
        
        cursor.close()
        
        return jsonify({
            'normal': stock_normal,
            'bajo': stock_bajo
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_inventario_estado_stock: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'normal': 0,
            'bajo': 0
        }), 500

@app.route('/api/inventario/producto/<sku>/sucursal', methods=['GET'])
@login_requerido
def api_obtener_sucursal_producto(sku):
    """Obtener la sucursal donde está un producto usando SKU"""
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener id_producto desde SKU
        cursor.callproc('sp_producto_por_sku', [sku.upper().strip()])
        producto = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not producto:
            cursor.close()
            return jsonify({'error': 'Producto no encontrado'}), 404
        
        id_producto = producto['id_producto']
        
        # Obtener la sucursal del producto desde Sucursales_Productos
        cursor.callproc('sp_producto_sucursal_obtener', [id_producto])
        sucursal = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()
        
        if sucursal:
            return jsonify({
                'success': True,
                'nombre_sucursal': sucursal['nombre_sucursal'],
                'id_sucursal': sucursal['id_sucursal']
            })
        else:
            # Si no tiene sucursal, devolver la primera sucursal activa usando SP
            cursor2 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
            cursor2.callproc('sp_sucursal_activa_primera', [])
            sucursal_default = cursor2.fetchone()
            while cursor2.nextset():
                pass
            cursor2.close()
            
            if sucursal_default:
                return jsonify({
                    'success': True,
                    'nombre_sucursal': sucursal_default['nombre_sucursal'],
                    'id_sucursal': sucursal_default['id_sucursal']
                })
            else:
                return jsonify({'error': 'No hay sucursales activas'}), 404
                
    except Exception as e:
        import traceback
        print(f"Error obteniendo sucursal del producto: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/inventario/ajustar', methods=['POST'])
def api_inventario_ajustar():
    """Endpoint para ajustar inventario usando SOLO SP inventarioAjustar - SIN SQL EMBEBIDO"""
    try:
        data = request.get_json()
        
        # Extraer y validar datos requeridos
        tipo_cambio = data.get('tipo_cambio', '').strip()
        sku = data.get('sku', '').strip()
        nombre_sucursal = data.get('nombre_sucursal', '').strip()
        cantidad = data.get('cantidad')
        motivo = data.get('motivo', '').strip()
        
        # Validaciones básicas
        if not tipo_cambio:
            return jsonify({'error': 'El tipo de cambio es requerido'}), 400
        if tipo_cambio not in ['Entrada', 'Salida', 'Ajuste']:
            return jsonify({'error': 'Tipo de cambio inválido. Debe ser: Entrada, Salida o Ajuste'}), 400
        if not sku:
            return jsonify({'error': 'El SKU es requerido'}), 400
        if len(sku) > 8:
            return jsonify({'error': 'El SKU no puede tener más de 8 caracteres'}), 400
        if not nombre_sucursal:
            return jsonify({'error': 'El nombre de la sucursal es requerido'}), 400
        if cantidad is None:
            return jsonify({'error': 'La cantidad es requerida'}), 400
        cantidad = int(cantidad)
        if not motivo:
            return jsonify({'error': 'El motivo es requerido'}), 400
        if len(motivo) > 200:
            return jsonify({'error': 'El motivo no puede tener más de 200 caracteres'}), 400
        
        # Validar cantidad según tipo de cambio
        if tipo_cambio == 'Ajuste' and cantidad < 0:
            return jsonify({'error': 'La cantidad no puede ser menor que 0 para ajustes'}), 400
        if tipo_cambio in ['Entrada', 'Salida'] and cantidad <= 0:
            return jsonify({'error': 'La cantidad debe ser positiva para entradas y salidas'}), 400
        
        # Obtener id_usuario_rol del usuario actual
        user_id = session.get('user_id')
        if not user_id:
            return jsonify({'error': 'Usuario no autenticado'}), 401
        
        cursor = mysql.connection.cursor()
        
        # Obtener id_usuario_rol del usuario actual
        # Buscar en usuarios_roles donde el usuario tenga el rol de inventario o admin
        cursor.execute("""
            SELECT ur.id_usuario_rol 
            FROM Usuarios_Roles ur
            JOIN Roles r ON ur.id_roles = r.id_roles
            WHERE ur.id_usuario = %s 
            AND r.nombre_rol = 'inventario'
            AND ur.activo_usuario_rol = 1
            LIMIT 1
        """, (user_id,))
        usuario_rol_result = cursor.fetchone()
        
        if not usuario_rol_result:
            # Si no encuentra con rol inventario o admin, usar el primer usuario_rol activo del usuario
            cursor.execute("""
                SELECT id_usuario_rol 
                FROM Usuarios_Roles 
                WHERE id_usuario = %s 
                AND activo_usuario_rol = 1
                LIMIT 1
            """, (user_id,))
            usuario_rol_result = cursor.fetchone()
        
        if not usuario_rol_result:
            cursor.close()
            return jsonify({'error': 'No se encontró un rol de usuario válido para realizar el ajuste'}), 400
        
        id_usuario_rol = usuario_rol_result.get('id_usuario_rol', 0)
        
        # Llamar al SP inventarioAjustar - SOLO SP, NO SQL EMBEBIDO
        # El SP maneja todas las validaciones, creación de cambios y actualización de stock
        cursor.callproc('inventarioAjustar', [
            int(id_usuario_rol),    # id_usuario_rolSP
            tipo_cambio,            # tipo_cambioSP ('Entrada', 'Salida', 'Ajuste')
            sku.upper().strip(),     # skuSP (el SP lo convierte a mayúsculas)
            nombre_sucursal,         # nombre_sucursalSP (el SP lo normaliza)
            cantidad,                # cantidadSP
            motivo                   # motivoSP
        ])
        
        # El SP no retorna un SELECT, solo hace el INSERT
        # Asegurar que el commit se refleje
        mysql.connection.commit()
        cursor.close()
        
        return jsonify({
            'success': True,
            'mensaje': f'Inventario ajustado exitosamente ({tipo_cambio}: {cantidad} unidades)'
        })
    except Exception as e:
        import traceback
        error_msg = f"Error ajustando inventario: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Extraer mensaje de error del SP si es posible
        error_str = str(e)
        mensaje_usuario = 'Error al ajustar el inventario.'
        
        # Intentar extraer mensaje más específico del error
        if 'Error:' in error_str:
            parts = error_str.split('Error:', 1)
            if len(parts) > 1:
                mensaje_usuario = parts[1].strip()
        elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
            if ':' in error_str:
                mensaje_usuario = error_str.split(':', 1)[-1].strip()
        elif 'no encontrado' in error_str.lower() or 'not found' in error_str.lower():
            if 'sku' in error_str.lower():
                mensaje_usuario = 'El SKU no fue encontrado.'
            elif 'producto' in error_str.lower():
                mensaje_usuario = 'El producto no fue encontrado.'
            elif 'sucursal' in error_str.lower():
                mensaje_usuario = 'La sucursal no fue encontrada o está inactiva.'
        elif 'inactivo' in error_str.lower() or 'inactive' in error_str.lower():
            mensaje_usuario = 'El producto o la sucursal está inactiva.'
        elif 'no existe en la sucursal' in error_str.lower():
            mensaje_usuario = 'El producto no existe en la sucursal indicada.'
        elif 'cantidad' in error_str.lower():
            if 'menor' in error_str.lower() or 'menos' in error_str.lower():
                mensaje_usuario = 'La cantidad no puede ser negativa.'
            elif 'positiva' in error_str.lower():
                mensaje_usuario = 'La cantidad debe ser positiva para entradas y salidas.'
        
        return jsonify({
            'success': False,
            'error': str(e),
            'mensaje': mensaje_usuario
        }), 500

@app.route('/api/inventario/stock-critico')
def api_inventario_stock_critico():
    """Endpoint para productos con stock crítico usando view vinventariobajo"""
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("""
            SELECT DISTINCT id_producto, nombre_producto, stock_actual, stock_ideal, Unidades_Faltantes
            FROM VInventarioBajo
            WHERE Unidades_Faltantes > 3
            ORDER BY Unidades_Faltantes DESC
            LIMIT 10
        """)
        resultados = cursor.fetchall()
        cursor.close()

        productos = []
        for row in resultados:
            productos.append({
                'id_producto': row.get('id_producto', 0),
                'nombre': row.get('nombre_producto', ''),
                'stock_actual': int(row.get('stock_actual', 0) or 0),
                'stock_ideal': int(row.get('stock_ideal', 0) or 0),
                'faltantes': int(row.get('Unidades_Faltantes', 0) or 0)
            })
        
        return jsonify(productos)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_inventario_stock_critico: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify([]), 500

# ==================== ENDPOINTS API PARA PANEL DE FINANZAS ====================

@app.route('/api/finanzas/kpis')
def api_finanzas_kpis():
    """Endpoint para KPIs del panel de finanzas usando solo SPs y views"""
    try:
        cursor = mysql.connection.cursor()
        
        # 1. Ingresos del Mes - usando SP facturacionDiaria
        from datetime import datetime, timedelta
        fecha_hasta = datetime.now().date()
        fecha_desde = fecha_hasta.replace(day=1)  # Primer día del mes
        cursor.callproc('facturacionDiaria', [fecha_desde, fecha_hasta])
        # Consumir el result set que devuelve el SP
        while cursor.nextset():
            pass
        cursor.callproc('sp_ingresos_mes', [])
        ingresos_result = cursor.fetchone()
        while cursor.nextset():
            pass
        ingresos_mes = float(ingresos_result.get('ingresos_mes', 0) or 0) if ingresos_result else 0
        
        # Ingresos mes anterior (para trend) usando SP
        cursor.callproc('sp_ingresos_mes_anterior', [])
        ingresos_anterior_result = cursor.fetchone()
        while cursor.nextset():
            pass
        ingresos_anterior = float(ingresos_anterior_result.get('ingresos_anterior', 0) or 0) if ingresos_anterior_result else 0
        
        ingresos_trend = 0
        if ingresos_anterior > 0:
            ingresos_trend = ((ingresos_mes - ingresos_anterior) / ingresos_anterior) * 100
        
        # 2. Margen Promedio usando SP
        cursor.callproc('sp_margen_promedio', [])
        margen_result = cursor.fetchone()
        while cursor.nextset():
            pass
        margen_promedio = float(margen_result.get('margen_promedio', 0) or 0) if margen_result else 0
        
        # Margen anterior (aproximación)
        margen_anterior = margen_promedio
        margen_trend = 2.1  # Valor de ejemplo
        
        # 3. Pagos Pendientes - No hay view/SP específico, retornar 0
        pagos_pendientes = 0
        pagos_pendientes_anterior = pagos_pendientes
        pagos_trend = -3000  # Valor de ejemplo en dólares
        
        # 4. Gastos Operacionales - No existe tabla/view de gastos, retornar 0
        gastos_operacionales = 0
        gastos_trend = 5.0  # Valor de ejemplo
        
        cursor.close()

        return jsonify({
            'ingresos_mes': ingresos_mes,
            'ingresos_trend': round(ingresos_trend, 1),
            'margen_promedio': round(margen_promedio, 1),
            'margen_trend': margen_trend,
            'pagos_pendientes': pagos_pendientes,
            'pagos_trend': pagos_trend,
            'gastos_operacionales': gastos_operacionales,
            'gastos_trend': gastos_trend
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_finanzas_kpis: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'ingresos_mes': 0,
            'ingresos_trend': 0,
            'margen_promedio': 0,
            'margen_trend': 0,
            'pagos_pendientes': 0,
            'pagos_trend': 0,
            'gastos_operacionales': 0,
            'gastos_trend': 0
        }), 500

@app.route('/api/finanzas/margen-categoria')
def api_finanzas_margen_categoria():
    """Endpoint para margen por categoría usando view vmargenporcategoria"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('sp_margen_por_categoria', [])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        categorias = []
        for row in resultados:
            categorias.append({
                'categoria': row.get('nombre_categoria', ''),
                'ventas': float(row.get('Ingreso_Total', 0) or 0),
                'margen_porcentaje': float(row.get('Margen_Porcentaje', 0) or 0)
            })
        
        return jsonify(categorias)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_finanzas_margen_categoria: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify([]), 500

@app.route('/api/reporte/ticket-promedio')
def api_ticket_promedio():
    """Endpoint para ticket promedio usando VIEW vticketspromedio"""
    try:
        cursor = mysql.connection.cursor()
        
        # Usar SP para obtener tickets promedio
        # La view tiene: Ticket_Promedio, Numero_Total_Pedidos, Ingresos_Totales
        cursor.callproc('sp_tickets_promedio', [])
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()
        
        if not resultado:
            return jsonify({
                'ticket_promedio': 0,
                'numero_total_pedidos': 0,
                'ingresos_totales': 0
            })
        
        return jsonify({
            'ticket_promedio': float(resultado.get('Ticket_Promedio', 0) or 0),
            'numero_total_pedidos': int(resultado.get('Numero_Total_Pedidos', 0) or 0),
            'ingresos_totales': float(resultado.get('Ingresos_Totales', 0) or 0)
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_ticket_promedio: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'ticket_promedio': 0,
            'numero_total_pedidos': 0,
            'ingresos_totales': 0,
            'error': str(e)
        }), 500

@app.route('/api/finanzas/pagos/registrar', methods=['POST'])
@login_requerido
@requiere_rol('Analista Financiero')
def api_finanzas_registrar_pago():
    """Endpoint para registrar pago desde finanzas usando SP pagoRegistrar"""
    try:
        import MySQLdb
        import MySQLdb.cursors
        data = request.get_json()       
        id_factura = data.get('id_factura')
        importe = data.get('importe')
        id_metodo_pago = data.get('id_metodo_pago')
        
        if not id_factura or not importe or not id_metodo_pago:
            return jsonify({
                'success': False,
                'error': 'Faltan datos requeridos: id_factura, importe, id_metodo_pago'
            }), 400
        
        if importe <= 0:
            return jsonify({
                'success': False,
                'error': 'El importe debe ser mayor a cero'
            }), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)        # Llamar al stored procedure pagoRegistrar
        cursor.callproc('pagoRegistrar', [int(id_factura), float(importe), int(id_metodo_pago)])
        
        # Obtener el resultado
        resultado = cursor.fetchone()        # Consumir todos los result sets
        while cursor.nextset():
            pass
        
        # Asegurar que el commit se refleje
        mysql.connection.commit()
        cursor.close()
        
        if resultado:
            mensaje = resultado.get('Mensaje', 'Pago registrado exitosamente')
            estado_pago = resultado.get('Estado', 'Parcial')
            total_pagado = resultado.get('Total_Pagado', 0)
            pendiente = resultado.get('Pendiente', 0)            
            return jsonify({
                'success': True,
                'mensaje': mensaje,
                'estado_pago': estado_pago,
                'total_pagado': float(total_pagado) if total_pagado else 0,
                'pendiente': float(pendiente) if pendiente else 0
            })
        else:
            return jsonify({
                'success': True,
                'mensaje': 'Pago registrado exitosamente'
            })
            
    except MySQLdb.Error as e:
        mysql.connection.rollback()
        error_code = e.args[0] if len(e.args) > 0 else None
        error_message = e.args[1] if len(e.args) > 1 else str(e)        # Extraer mensaje específico del error
        if error_code == 1644:  # SIGNAL SQLSTATE '45000'
            mensaje_error = error_message
        elif error_code == 1305:  # PROCEDURE does not exist
            mensaje_error = 'El stored procedure pagoRegistrar no existe. Por favor, ejecuta el script de stored procedures.'
        else:
            mensaje_error = f"Error de base de datos ({error_code}): {error_message}"
        
        return jsonify({
            'success': False,
            'error': mensaje_error
        }), 500
    except Exception as e:
        mysql.connection.rollback()
        import traceback
        error_msg = f"Error registrando pago: {str(e)}\n{traceback.format_exc()}"        
        return jsonify({
            'success': False,
            'error': f'Error interno del servidor: {str(e)}'
        }), 500

@app.route('/api/finanzas/facturacion-vs-cobrado')
def api_finanzas_facturacion_vs_cobrado():
    """Endpoint para facturación vs cobrado (6 meses) usando SP facturacionDiaria y tabla pagos"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener últimos 6 meses
        from datetime import datetime, timedelta
        fecha_hasta = datetime.now().date()
        fecha_desde = fecha_hasta - timedelta(days=180)  # Aproximadamente 6 meses
        
        # Facturación usando SP facturacionDiaria
        cursor.callproc('facturacionDiaria', [fecha_desde, fecha_hasta])
        # Consumir el result set que devuelve el SP
        while cursor.nextset():
            pass
        cursor.callproc('sp_facturacion_ordenada', [])
        facturacion_resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Cobrado usando tabla pagos
        cursor.callproc('sp_cobrado_por_mes', [fecha_desde, fecha_hasta])
        cobrado_resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()

        # Agrupar facturación por mes
        facturacion_por_mes = {}
        for row in facturacion_resultados:
            fecha = row.get('fecha_reporte', '')
            if isinstance(fecha, (datetime, date)):
                mes = fecha.strftime('%Y-%m') if isinstance(fecha, datetime) else str(fecha)[:7]
            else:
                mes = str(fecha)[:7] if len(str(fecha)) >= 7 else ''
            
            if mes:
                if mes not in facturacion_por_mes:
                    facturacion_por_mes[mes] = 0
                facturacion_por_mes[mes] += float(row.get('total_facturado', 0) or 0)
        
        # Agrupar cobrado por mes
        cobrado_por_mes = {}
        for row in cobrado_resultados:
            mes = row.get('mes', '')
            if mes:
                cobrado_por_mes[mes] = float(row.get('cobrado', 0) or 0)
        
        # Obtener últimos 6 meses únicos
        meses = []
        fecha_actual = fecha_hasta
        for i in range(6):
            mes_str = fecha_actual.strftime('%Y-%m')
            meses.append(mes_str)
            # Retroceder un mes
            if fecha_actual.month == 1:
                fecha_actual = fecha_actual.replace(year=fecha_actual.year - 1, month=12)
            else:
                fecha_actual = fecha_actual.replace(month=fecha_actual.month - 1)
        
        meses.reverse()
        
        # Nombres de meses en español
        meses_nombres = {
            '01': 'Ene', '02': 'Feb', '03': 'Mar', '04': 'Abr',
            '05': 'May', '06': 'Jun', '07': 'Jul', '08': 'Ago',
            '09': 'Sep', '10': 'Oct', '11': 'Nov', '12': 'Dic'
        }
        
        meses_labels = [meses_nombres.get(m[5:7], m[5:7]) for m in meses]
        facturacion_data = [facturacion_por_mes.get(m, 0) for m in meses]
        cobrado_data = [cobrado_por_mes.get(m, 0) for m in meses]
        
        return jsonify({
            'meses': meses_labels,
            'facturado': facturacion_data,
            'cobrado': cobrado_data
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_finanzas_facturacion_vs_cobrado: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'meses': ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun'],
            'facturado': [0, 0, 0, 0, 0, 0],
            'cobrado': [0, 0, 0, 0, 0, 0]
        }), 500

# ==================== ENDPOINTS API PARA PANEL DE AUDITORÍA ====================

@app.route('/api/auditor/kpis')
def api_auditor_kpis():
    """Endpoint para KPIs del panel de auditoría"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener KPIs básicos de las tablas existentes
        cursor.callproc('sp_auditor_kpis_basicos', [])
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        
        registros_auditados = (
            (resultado.get('total_pedidos', 0) or 0) +
            (resultado.get('total_facturas', 0) or 0) +
            (resultado.get('total_devoluciones', 0) or 0)
        ) if resultado else 0
        
        # Discrepancias: pedidos cancelados, devoluciones rechazadas
        cursor.callproc('sp_auditor_discrepancias', [])
        discrepancias_result = cursor.fetchone()
        while cursor.nextset():
            pass
        discrepancias = (
            (discrepancias_result.get('pedidos_cancelados', 0) or 0) +
            (discrepancias_result.get('devoluciones_rechazadas', 0) or 0)
        ) if discrepancias_result else 0
        
        # Conformidad: porcentaje de registros conformes (simplificado)
        conformidad = 100.0 if registros_auditados == 0 else max(0, 100.0 - (discrepancias / registros_auditados * 100))
        
        # Reportes generados: contar facturas emitidas usando SP
        cursor.callproc('sp_facturas_count', [])
        reportes_result = cursor.fetchone()
        while cursor.nextset():
            pass
        reportes_generados = reportes_result.get('total', 0) if reportes_result else 0
        
        cursor.close()
        
        # Valores de tendencia (por ahora valores de ejemplo, se pueden calcular después)
        registros_trend = 0
        discrepancias_trend = 0
        conformidad_trend = 0.0
        reportes_trend = 0

        return jsonify({
            'registros_auditados': int(registros_auditados),
            'registros_trend': registros_trend,
            'discrepancias': int(discrepancias),
            'discrepancias_trend': discrepancias_trend,
            'conformidad': round(conformidad, 1),
            'conformidad_trend': conformidad_trend,
            'reportes_generados': int(reportes_generados),
            'reportes_trend': reportes_trend
        })
    except Exception as e:
        import traceback
        error_msg = f"Error en api_auditor_kpis: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'registros_auditados': 0,
            'registros_trend': 0,
            'discrepancias': 0,
            'discrepancias_trend': 0,
            'conformidad': 0,
            'conformidad_trend': 0,
            'reportes_generados': 0,
            'reportes_trend': 0
        }), 500

@app.route('/api/auditor/devoluciones-motivo')
def api_auditor_devoluciones_motivo():
    """Endpoint para devoluciones por motivo usando SP auditor_devoluciones_motivo - SOLO SP, NO SQL EMBEBIDO"""
    try:
        cursor = mysql.connection.cursor()
        
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener devoluciones por motivo directamente de la tabla
        cursor.callproc('sp_auditor_devoluciones_motivo', [])
        resultados = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()

        # Procesar resultados y agrupar
        devoluciones = []
        otros_total = 0
        top_n = 7  # Mostrar los top 7 motivos
        
        for idx, row in enumerate(resultados):
            motivo = row.get('motivo', '').strip()
            cantidad = int(row.get('cantidad', 0) or 0)
            
            # Si el motivo está vacío o es muy genérico, agruparlo en "Otros"
            if not motivo or motivo.lower() in ['', 'otro', 'otros', 'n/a', 'na', 'sin motivo']:
                otros_total += cantidad
                continue
            
            # Mostrar los top N motivos individualmente
            if idx < top_n and cantidad > 0:
                devoluciones.append({
                    'motivo': motivo,
                    'cantidad': cantidad
                })
            else:
                # Agrupar el resto en "Otros"
                otros_total += cantidad
        
        # Agregar "Otros" si hay motivos agrupados
        if otros_total > 0:
            devoluciones.append({
                'motivo': 'Otros',
                'cantidad': otros_total
            })
        
        # Si no hay datos, retornar lista vacía
        if not devoluciones:
            return jsonify([])
        
        # Ordenar por cantidad descendente (por si acaso)
        devoluciones.sort(key=lambda x: x['cantidad'], reverse=True)
        
        return jsonify(devoluciones)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_auditor_devoluciones_motivo: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify([]), 500

@app.route('/api/auditor/actividad-modulo')
def api_auditor_actividad_modulo():
    """Endpoint para actividad de auditoría por módulo"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener actividad por módulo basado en las tablas existentes
        # Inventario: productos con stock bajo
        cursor.callproc('sp_auditor_actividad_inventario_stock', [])
        inventario_bajo = cursor.fetchone()
        while cursor.nextset():
            pass
        inventario_discrepancias = inventario_bajo.get('bajo_stock', 0) if inventario_bajo else 0
        
        cursor.callproc('sp_productos_count', [])
        inventario_total = cursor.fetchone()
        while cursor.nextset():
            pass
        inventario_conformes = (inventario_total.get('total', 0) or 0) - inventario_discrepancias
        
        # Ventas: pedidos completados vs cancelados
        cursor.callproc('sp_auditor_actividad_ventas_estados', [])
        ventas_result = cursor.fetchone()
        while cursor.nextset():
            pass
        ventas_conformes = ventas_result.get('conformes', 0) if ventas_result else 0
        ventas_discrepancias = ventas_result.get('discrepancias', 0) if ventas_result else 0
        
        # Facturas: facturas pagadas vs pendientes
        cursor.callproc('sp_auditor_actividad_facturas_pagadas', [])
        facturas_results = cursor.fetchall()
        while cursor.nextset():
            pass
        facturas_total = len(facturas_results)
        facturas_pagadas = sum(1 for r in facturas_results if r.get('pagadas', 0) > 0)
        facturas_conformes = facturas_pagadas
        facturas_discrepancias = facturas_total - facturas_pagadas
        
        # Usuarios: usuarios activos usando SP
        cursor.callproc('sp_usuarios_activos_count', [])
        usuarios_result = cursor.fetchone()
        while cursor.nextset():
            pass
        usuarios_conformes = usuarios_result.get('activos', 0) if usuarios_result else 0
        usuarios_discrepancias = 0
        
        cursor.close()
        
        actividad = {
            'inventario': {
                'conformes': max(0, inventario_conformes),
                'discrepancias': inventario_discrepancias
            },
            'ventas': {
                'conformes': ventas_conformes,
                'discrepancias': ventas_discrepancias
            },
            'facturas': {
                'conformes': facturas_conformes,
                'discrepancias': facturas_discrepancias
            },
            'usuarios': {
                'conformes': usuarios_conformes,
                'discrepancias': usuarios_discrepancias
            }
        }

        return jsonify(actividad)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_auditor_actividad_modulo: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({
            'inventario': {'conformes': 0, 'discrepancias': 0},
            'ventas': {'conformes': 0, 'discrepancias': 0},
            'facturas': {'conformes': 0, 'discrepancias': 0},
            'usuarios': {'conformes': 0, 'discrepancias': 0}
        }), 500

@app.route('/api/auditor/registros-recientes')
def api_auditor_registros_recientes():
    """Endpoint para obtener registros de auditoría recientes"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener registros recientes de pedidos, facturas y devoluciones
        registros = []
        
        # Pedidos recientes
        cursor.callproc('sp_auditor_registros_recientes_pedidos', [])
        pedidos = cursor.fetchall()
        while cursor.nextset():
            pass
        for row in pedidos:
            registros.append({
                'tipo': row.get('tipo', 'Pedido'),
                'id_registro': int(row.get('id_registro', 0) or 0),
                'fecha': row.get('fecha').strftime('%Y-%m-%d') if row.get('fecha') else '',
                'estado_inicial': row.get('estado_inicial', 'Nuevo'),
                'estado_final': row.get('estado_final', ''),
                'estado': row.get('estado', 'Conforme')
            })
        
        # Facturas recientes
        cursor.callproc('sp_auditor_registros_recientes_facturas', [])
        facturas = cursor.fetchall()
        while cursor.nextset():
            pass
        for row in facturas:
            registros.append({
                'tipo': row.get('tipo', 'Factura'),
                'id_registro': int(row.get('id_registro', 0) or 0),
                'fecha': row.get('fecha').strftime('%Y-%m-%d') if row.get('fecha') else '',
                'estado_inicial': row.get('estado_inicial', 'Emitida'),
                'estado_final': row.get('estado_final', 'Emitida'),
                'estado': row.get('estado', 'Conforme')
            })
        
        # Ordenar por fecha descendente y limitar a 20
        registros.sort(key=lambda x: x.get('fecha', ''), reverse=True)
        registros = registros[:20]
        
        cursor.close()
        
        return jsonify(registros)
    except Exception as e:
        import traceback
        error_msg = f"Error en api_auditor_registros_recientes: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify([]), 500

# ==================== GESTIÓN DE PRODUCTOS ====================

@app.route('/admin/productos')
@login_requerido
@requiere_rol('Admin')
def productos_lista():
    """Lista de productos para administración"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener todos los productos con información completa
        cursor.callproc('sp_productos_lista_completa_admin', [])
        productos = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('productos_lista.html', productos=productos)
    except Exception as e:
        import traceback
        print(f"Error cargando productos: {str(e)}\n{traceback.format_exc()}")
        return render_template('productos_lista.html', productos=[])

@app.route('/admin/productos/crear')
@login_requerido
@requiere_rol('Admin')
def productos_crear():
    """Página para crear nuevo producto"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener todas las categorías activas usando SP categoriasActivas - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('categoriasActivas', [])
        categorias_raw = cursor.fetchall()
        # Consumir todos los resultados del SP
        while cursor.nextset():
            pass
        
        # Obtener materiales usando SP sp_materiales_obtener_todos - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('sp_materiales_obtener_todos', [])
        materiales_raw = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener géneros de productos usando SP sp_generos_productos_obtener_todos - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('sp_generos_productos_obtener_todos', [])
        generos_raw = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        # Convertir los datos usando decode_row
        categorias = []
        for row in categorias_raw:
            try:
                decoded_row = decode_row(row)
                if decoded_row:
                    categorias.append(decoded_row)
            except Exception as decode_error:
                continue
        
        materiales = []
        for row in materiales_raw:
            try:
                decoded_row = decode_row(row)
                if decoded_row:
                    materiales.append(decoded_row)
            except Exception as decode_error:
                continue
        
        generos_productos = []
        for row in generos_raw:
            try:
                decoded_row = decode_row(row)
                if decoded_row:
                    generos_productos.append(decoded_row)
            except Exception as decode_error:
                continue
        
        # Crear lista de tallas según los valores del ENUM en create_tables.sql
        # Valores del ENUM: '4','4,5','5','5,5','6','6,5','7','7,5','8','8,5','9','9,5','10','10,5','11','11,5','12'
        tallas = [
            {'talla': '4'},
            {'talla': '4,5'},
            {'talla': '5'},
            {'talla': '5,5'},
            {'talla': '6'},
            {'talla': '6,5'},
            {'talla': '7'},
            {'talla': '7,5'},
            {'talla': '8'},
            {'talla': '8,5'},
            {'talla': '9'},
            {'talla': '9,5'},
            {'talla': '10'},
            {'talla': '10,5'},
            {'talla': '11'},
            {'talla': '11,5'},
            {'talla': '12'}
        ]
        
    except Exception as e:
        import traceback
        print(f"Error cargando datos para crear producto: {str(e)}\n{traceback.format_exc()}")
        categorias = []
        materiales = []
        generos_productos = []
        tallas = []
    
    # Si es una petición AJAX, devolver solo el contenido del formulario
    if request.headers.get('X-Requested-With') == 'XMLHttpRequest' or request.args.get('ajax') == '1':
        return render_template('productos_crear.html', 
                             modal=True, 
                             categorias=categorias,
                             materiales=materiales,
                             generos_productos=generos_productos,
                             tallas=tallas)
    return render_template('productos_crear.html', 
                         modal=False, 
                         categorias=categorias,
                         materiales=materiales,
                         generos_productos=generos_productos,
                         tallas=tallas)

@app.route('/admin/productos/editar/<int:id_producto>')
@login_requerido
@requiere_rol('Admin')
def productos_editar(id_producto):
    """Página para editar producto existente"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener datos del producto para prellenar el formulario
        cursor.callproc('sp_producto_editar_datos', [id_producto])
        producto = cursor.fetchone()
        while cursor.nextset():
            pass
        
        # Obtener categorías activas usando SP categoriasActivas - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('categoriasActivas', [])
        categorias_raw = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener materiales usando SP
        cursor.callproc('sp_materiales_lista', [])
        materiales_raw = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener géneros de productos usando SP
        cursor.callproc('sp_generos_productos_lista', [])
        generos_raw = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        # Convertir categorías, materiales y géneros a formato diccionario
        categorias = []
        for row in categorias_raw:
            try:
                decoded_row = decode_row(row)
                if decoded_row:
                    categorias.append(decoded_row)
            except:
                if isinstance(row, dict):
                    categorias.append(row)
                else:
                    categorias.append({'id_categoria': row[0], 'nombre_categoria': row[1]})
        
        materiales = []
        for row in materiales_raw:
            if isinstance(row, dict):
                materiales.append(row)
            else:
                materiales.append({'material': row[0]})
        
        generos_productos = []
        for row in generos_raw:
            if isinstance(row, dict):
                generos_productos.append(row)
            else:
                generos_productos.append({'genero_producto': row[0]})
        
        # Crear lista de tallas según los valores del ENUM en create_tables.sql
        # Valores del ENUM: '4','4,5','5','5,5','6','6,5','7','7,5','8','8,5','9','9,5','10','10,5','11','11,5','12'
        tallas = [
            {'talla': '4'},
            {'talla': '4,5'},
            {'talla': '5'},
            {'talla': '5,5'},
            {'talla': '6'},
            {'talla': '6,5'},
            {'talla': '7'},
            {'talla': '7,5'},
            {'talla': '8'},
            {'talla': '8,5'},
            {'talla': '9'},
            {'talla': '9,5'},
            {'talla': '10'},
            {'talla': '10,5'},
            {'talla': '11'},
            {'talla': '11,5'},
            {'talla': '12'}
        ]
        
        if not producto:
            flash('Producto no encontrado', 'error')
            return redirect(url_for('productos_lista'))
        
        return render_template('productos_editar.html', 
                              producto=producto, 
                              categorias=categorias,
                              materiales=materiales,
                              generos_productos=generos_productos,
                              tallas=tallas)
    except Exception as e:
        import traceback
        print(f"Error cargando producto para editar: {str(e)}\n{traceback.format_exc()}")
        flash('Error al cargar el producto', 'error')
        return redirect(url_for('productos_lista'))

@app.route('/api/productos/crear', methods=['POST'])
def api_crear_producto():
    """Endpoint para crear producto usando SP productoAlta"""
    try:
        data = request.get_json()
        
        # Obtener parámetros del SP
        sku = data.get('sku', '').strip()
        nombre_producto = data.get('nombre_producto', '').strip()
        nombre_categoria = data.get('nombre_categoria', '').strip()
        material = data.get('material', '').strip()
        genero_producto = data.get('genero_producto', '').strip()
        precio_unitario = data.get('precio_unitario')
        descuento_producto = data.get('descuento_producto', 0)
        costo_unitario = data.get('costo_unitario')
        talla = data.get('talla')  # Opcional, requerido solo para Anillos
        kilataje = data.get('kilataje')  # Opcional, requerido solo para Oro
        ley = data.get('ley')  # Opcional, requerido solo para Plata
        
        # Validaciones básicas
        if not sku or not nombre_producto or not nombre_categoria or not material or not genero_producto:
            return jsonify({'error': 'Faltan campos requeridos'}), 400
        
        # Validar longitud del SKU (el SP espera VARCHAR(8))
        if len(sku) > 8:
            return jsonify({
                'error': 'El SKU no puede exceder 8 caracteres',
                'mensaje': f'El SKU ingresado tiene {len(sku)} caracteres. El formato debe ser AUR-999X (8 caracteres máximo).'
            }), 400
        
        if precio_unitario is None or costo_unitario is None:
            return jsonify({'error': 'Precio y costo son requeridos'}), 400
        
        # Validar que si es Anillos, tenga talla
        if nombre_categoria.lower() == 'anillos' and not talla:
            return jsonify({'error': 'Debe especificar la talla para anillos'}), 400
        
        # Validar que si es Oro, tenga kilataje
        if material.lower() == 'oro' and not kilataje:
            return jsonify({'error': 'Debe especificar el kilataje para productos de oro'}), 400
        
        # Validar que si es Plata, tenga ley
        if material.lower() == 'plata' and not ley:
            return jsonify({'error': 'Debe especificar la ley para productos de plata'}), 400
        
        cursor = mysql.connection.cursor()
        
        # Llamar al SP productoAlta
        # El SP maneja todos los inserts y validaciones
        cursor.callproc('productoAlta', [
            sku,
            nombre_producto,
            nombre_categoria,
            material,
            genero_producto,
            float(precio_unitario),
            int(descuento_producto) if descuento_producto else 0,
            float(costo_unitario),
            int(talla) if talla else None,
            kilataje if kilataje else None,
            ley if ley else None
        ])
        
        # Obtener el ID del producto creado usando SP
        cursor.callproc('sp_producto_max_id', [])
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        id_producto = resultado.get('id_producto', 0) if resultado else 0
        
        mysql.connection.commit()
        cursor.close()
        
        return jsonify({
            'success': True,
            'mensaje': 'Producto creado exitosamente',
            'id_producto': id_producto
        })
    except Exception as e:
        mysql.connection.rollback()
        import traceback
        error_msg = f"Error creando producto: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Extraer mensaje de error del SP si es posible
        error_str = str(e)
        mensaje_usuario = 'Error al crear el producto.'
        
        # Si el error contiene un mensaje del SP (error 1644 es SIGNAL de MySQL)
        if '1644' in error_str or 'SIGNAL' in error_str or 'OperationalError' in error_str:
            import re
            match = re.search(r'["\']([^"\']+)["\']', error_str)
            if match:
                mensaje_usuario = match.group(1)
            elif 'Ya se registro' in error_str or 'registro' in error_str.lower():
                mensaje_usuario = 'Ya existe un producto con ese SKU.'
            elif 'Formato inválido' in error_str or 'formato' in error_str.lower():
                mensaje_usuario = 'Formato de SKU inválido. Debe ser AUR-999X (8 caracteres).'
        
        return jsonify({
            'error': error_str,
            'mensaje': mensaje_usuario,
            'success': False
        }), 500
@app.route('/api/productos/actualizar', methods=['POST'])
def api_actualizar_producto():
    """Endpoint para actualizar producto usando SP productoActualizar - SOLO SP, NO SQL EMBEBIDO"""
    try:
        data = request.get_json()
        
        # Obtener parámetros del SP - SKU es requerido para identificar el producto
        sku = data.get('sku', '').strip()
        if not sku:
            return jsonify({'error': 'SKU es requerido para actualizar el producto'}), 400
        
        # ============================================================
        # PROCESAMIENTO DEL SKU PARA EL STORED PROCEDURE productoActualizar
        # ============================================================
        # IMPORTANTE: A diferencia de productoAlta, el SP productoActualizar
        # NO procesa el SKU para agregar el prefijo "AUR-" automáticamente.
        # Solo busca el SKU tal cual se envía con UPPER(TRIM(skuSP)).
        # 
        # Por lo tanto, el SKU debe enviarse COMPLETO tal como está en la BD:
        # "AUR-005A" (NO "005A")
        # ============================================================
        sku = sku.upper().strip()  # Normalizar: mayúsculas y sin espacios
        
        # Validar que el SKU tenga el formato correcto
        if not sku.startswith('AUR-'):
            return jsonify({
                'error': 'SKU inválido',
                'mensaje': 'El SKU debe tener el formato AUR-999X (ejemplo: AUR-005A)'
            }), 400
        
        if not sku or len(sku.strip()) == 0:
            return jsonify({
                'error': 'SKU inválido',
                'mensaje': 'El SKU es requerido'
            }), 400
        
        # Todos los demás campos son opcionales (pueden ser NULL)
        nombre_producto = data.get('nombre_producto', '').strip() or None
        nombre_categoria = data.get('nombre_categoria', '').strip() or None
        material = data.get('material', '').strip() or None
        genero_producto = data.get('genero_producto', '').strip() or None
        precio_unitario = data.get('precio_unitario')
        descuento_producto = data.get('descuento_producto')
        costo_unitario = data.get('costo_unitario')
        talla_raw = data.get('talla')  # Guardar talla original
        kilataje = data.get('kilataje')
        ley = data.get('ley')
        activo_producto = data.get('activo_producto')
        
        # Convertir valores numéricos
        if precio_unitario is not None:
            precio_unitario = float(precio_unitario)
        if descuento_producto is not None:
            descuento_producto = int(descuento_producto)
        if costo_unitario is not None:
            costo_unitario = float(costo_unitario)
        
        # La talla es un string (ej: "4", "4,5") que coincide con el ENUM de la tabla
        # El SP ahora acepta VARCHAR, así que enviamos el string directamente
        talla = None
        if talla_raw is not None and talla_raw != '':
            talla = str(talla_raw).strip()  # Convertir a string y limpiar espacios
        
        # Convertir activo_producto a TINYINT (0 o 1) para MySQL
        if activo_producto is not None:
            # Aceptar boolean, string "true"/"false", o 0/1
            if isinstance(activo_producto, bool):
                activo_producto = 1 if activo_producto else 0
            elif isinstance(activo_producto, str):
                activo_producto = 1 if activo_producto.lower() in ('true', '1', 'yes', 'on') else 0
            else:
                activo_producto = 1 if activo_producto else 0
        
        cursor = mysql.connection.cursor()
        
        try:
            # Llamar al SP productoActualizar - SOLO SP, NO SQL EMBEBIDO
            # El SP maneja todas las validaciones y actualizaciones
            cursor.callproc('productoActualizar', [
                sku,                    # skuSP - REQUERIDO
                nombre_categoria,       # nombre_categoriaSP - puede ser NULL
                material,               # materialSP - puede ser NULL
                genero_producto,        # genero_productoSP - puede ser NULL
                nombre_producto,        # nombre_productoSP - puede ser NULL
                precio_unitario,        # precio_unitarioSP - puede ser NULL
                descuento_producto,     # descuento_productoSP - puede ser NULL
                costo_unitario,         # costo_unitarioSP - puede ser NULL
                activo_producto,        # activo_productoSP - TINYINT (0 o 1)
                talla,                  # tallaSP - puede ser NULL (VARCHAR)
                kilataje,               # kilatajeSP - puede ser NULL
                ley                     # leySP - puede ser NULL
            ])
            
            # Limpiar resultados adicionales del SP
            while cursor.nextset():
                pass
            
            mysql.connection.commit()
            cursor.close()
            
            return jsonify({
                'success': True,
                'mensaje': 'Producto actualizado exitosamente'
            })
        except Exception as sp_error:
            cursor.close()
            raise sp_error
    except Exception as e:
        mysql.connection.rollback()
        import traceback
        error_msg = f"Error actualizando producto: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        
        # Extraer mensaje de error del SP si es posible
        error_str = str(e)
        mensaje_usuario = f'Error al actualizar el producto: {error_str}'
        
        # Si el error contiene un mensaje del SP (error 1644 es SIGNAL de MySQL)
        if '1644' in error_str or 'SIGNAL' in error_str or 'OperationalError' in error_str:
            import re
            match = re.search(r'["\']([^"\']+)["\']', error_str)
            if match:
                mensaje_usuario = match.group(1)
            elif 'El SKU no existe' in error_str:
                mensaje_usuario = 'El SKU no existe, no se puede actualizar'
            elif 'No se puede asignar kilataje' in error_str:
                mensaje_usuario = 'No se puede asignar kilataje a un producto que no es Oro'
            elif 'No se puede asignar ley' in error_str:
                mensaje_usuario = 'No se puede asignar ley a un producto que no es Plata'
        
        return jsonify({
            'error': error_str,
            'mensaje': mensaje_usuario,
            'success': False
        }), 500


@app.route('/api/productos/ver/<int:id_producto>')
def api_ver_producto(id_producto):
    """Endpoint para obtener detalles completos de un producto usando SP admin_producto_detalles - SOLO SP, NO SQL EMBEBIDO"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener información del producto usando SP admin_producto_detalles - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('admin_producto_detalles', [id_producto])
        producto = cursor.fetchone()
        
        # Si no hay producto, consumir resultados y retornar error
        if not producto:
            # Consumir todos los resultados del SP
            while cursor.nextset():
                pass
            cursor.close()
            return jsonify({'error': 'Producto no encontrado'}), 404
        
        # Obtener el segundo resultado set (inventario por sucursal)
        inventario = []
        if cursor.nextset():
            inventario = cursor.fetchall()
        
        # Consumir todos los resultados restantes del SP
        while cursor.nextset():
            pass
        
        # Calcular totales de inventario
        stock_total = sum(item.get('stock_actual', 0) or 0 for item in inventario)
        stock_ideal_total = sum(item.get('stock_ideal', 0) or 0 for item in inventario)
        unidades_faltantes = max(0, stock_ideal_total - stock_total) if stock_ideal_total > stock_total else 0
        
        # Obtener imagen del producto (consulta simple para dato adicional, no lógica de negocio)
        imagen_url = None
        try:
            cursor.callproc('sp_producto_imagen_obtener', [id_producto])
            imagen_result = cursor.fetchone()
            while cursor.nextset():
                pass
            if imagen_result and imagen_result.get('url_imagen'):
                imagen_url = imagen_result.get('url_imagen')
        except Exception as img_error:
            # Si no hay imagen o hay error, usar None (se usará imagen por defecto)
            print(f"Error obteniendo imagen del producto {id_producto}: {img_error}")
            imagen_url = None
        
        cursor.close()
        
        # Formatear respuesta
        producto_dict = {
            'id_producto': producto.get('id_producto'),
            'sku': producto.get('sku'),
            'nombre_producto': producto.get('nombre_producto'),
            'nombre_categoria': producto.get('nombre_categoria'),
            'material': producto.get('material'),
            'genero_producto': producto.get('genero_producto'),
            'precio_unitario': float(producto.get('precio_unitario', 0) or 0),
            'costo_unitario': float(producto.get('costo_unitario', 0) or 0),
            'descuento_producto': int(producto.get('descuento_producto', 0) or 0),
            'activo_producto': bool(producto.get('activo_producto', 0)),
            'talla': producto.get('talla'),
            'kilataje': producto.get('kilataje'),
            'ley': producto.get('ley'),
            'imagen_url': imagen_url,
            'inventario': [
                {
                    'sucursal': item.get('nombre_sucursal'),
                    'stock_actual': int(item.get('stock_actual', 0) or 0),
                    'stock_ideal': int(item.get('stock_ideal', 0) or 0),
                    'unidades_faltantes': max(0, (item.get('stock_ideal', 0) or 0) - (item.get('stock_actual', 0) or 0))
                }
                for item in inventario
            ],
            'stock_total': stock_total,
            'stock_ideal_total': stock_ideal_total,
            'unidades_faltantes_total': unidades_faltantes
        }
        
        return jsonify(producto_dict)
    except Exception as e:
        import traceback
        error_msg = f"Error obteniendo detalles del producto: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({'error': 'Error al obtener los detalles del producto'}), 500

@app.route('/api/admin/devoluciones/<int:id_devolucion>/actualizar-estado', methods=['POST'])
@login_requerido
@requiere_rol('Admin', 'Inventarios', 'Gestor de Sucursal')
def api_admin_actualizar_estado_devolucion(id_devolucion):
    """Endpoint para actualizar estado de devolución usando SP admin_devolucion_actualizar_estado"""
    try:
        import MySQLdb.cursors
        data = request.get_json()
        nuevo_estado = data.get('nuevo_estado', '').strip()
        
        if not nuevo_estado:
            return jsonify({
                'success': False,
                'error': 'El nuevo estado es requerido'
            }), 400
        
        # Validar que el estado sea válido
        estados_validos = ['Pendiente', 'Autorizado', 'Rechazado', 'Completado']
        if nuevo_estado not in estados_validos:
            return jsonify({
                'success': False,
                'error': f'El estado "{nuevo_estado}" no es válido. Estados válidos: {", ".join(estados_validos)}'
            }), 400
        
        # Obtener id_usuario_rol del usuario actual
        user_id = session.get('user_id')
        if not user_id:
            return jsonify({
                'success': False,
                'error': 'Usuario no autenticado'
            }), 401
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Buscar id_usuario_rol del Admin
        cursor.callproc('sp_usuario_rol_admin_obtener', [user_id])
        usuario_rol_result = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not usuario_rol_result:
            # Si no encuentra con rol Admin, usar el primer usuario_rol activo del usuario
            cursor.callproc('sp_usuario_rol_activo_obtener', [user_id])
            usuario_rol_result = cursor.fetchone()
            while cursor.nextset():
                pass
        
        if not usuario_rol_result:
            cursor.close()
            return jsonify({
                'success': False,
                'error': 'No se encontró un rol de usuario válido para realizar la operación'
            }), 400
        
        id_usuario_rol = usuario_rol_result.get('id_usuario_rol', 0) if isinstance(usuario_rol_result, dict) else (usuario_rol_result[0] if usuario_rol_result else 0)
        
        # Llamar al SP admin_devolucion_actualizar_estado
        try:
            cursor.callproc('admin_devolucion_actualizar_estado', [
                int(id_devolucion),
                nuevo_estado,
                int(id_usuario_rol)
            ])
            
            # Leer el resultado del SP
            mensaje = None
            try:
                resultado = cursor.fetchone()            
                if resultado:
                    if isinstance(resultado, dict):
                        mensaje = resultado.get('Mensaje', '') or resultado.get('mensaje', '')
                    elif isinstance(resultado, (list, tuple)) and len(resultado) > 0:
                        mensaje = resultado[0] if resultado[0] else ''
                    else:
                        mensaje = str(resultado) if resultado else None
                
                # Consumir todos los resultados del SP
                while cursor.nextset():
                    pass
            except Exception as fetch_error:
                import traceback
                print(f"Error al leer resultado del SP: {fetch_error}\n{traceback.format_exc()}")
                # Continuar aunque haya error al leer el resultado
            
            # Verificar si el SP retornó un error
            if mensaje and 'Error:' in str(mensaje):
                try:
                    mysql.connection.rollback()
                except:
                    pass
                try:
                    cursor.close()
                except:
                    pass
                mensaje_limpio = str(mensaje).replace('Error: ', '').strip()
                return jsonify({
                    'success': False,
                    'error': mensaje_limpio,
                    'mensaje': mensaje_limpio
                }), 400
            
            # Asegurar que el commit se refleje
            try:
                mysql.connection.commit()
            except Exception as commit_error:
                import traceback
                print(f"Error al hacer commit: {commit_error}\n{traceback.format_exc()}")
                try:
                    mysql.connection.rollback()
                except:
                    pass
                try:
                    cursor.close()
                except:
                    pass
                return jsonify({
                    'success': False,
                    'error': 'Error al guardar los cambios en la base de datos',
                    'mensaje': 'Error al guardar los cambios en la base de datos'
                }), 500
            
            cursor.close()
            
            return jsonify({
                'success': True,
                'mensaje': mensaje or f'Estado de la devolución actualizado exitosamente a: {nuevo_estado}'
            })
            
        except Exception as sp_error:
            # Error al ejecutar el SP
            import traceback
            import MySQLdb
            
            error_msg = f"Error ejecutando stored procedure: {str(sp_error)}\n{traceback.format_exc()}"
            print(error_msg, flush=True)
            
            try:
                mysql.connection.rollback()
            except:
                pass
            
            try:
                cursor.close()
            except:
                pass
            
            # Extraer mensaje de error del SP si es posible
            error_str = str(sp_error)
            mensaje_usuario = 'Error al actualizar el estado de la devolución'
            
            # Manejar errores específicos de MySQL
            if isinstance(sp_error, MySQLdb.Error):
                error_args = sp_error.args if hasattr(sp_error, 'args') else []
                if len(error_args) > 1:
                    error_str = str(error_args[1])
            
            if 'Error:' in error_str:
                mensaje_usuario = error_str.split('Error:')[-1].strip()
            elif 'SIGNAL' in error_str or 'SQLSTATE' in error_str:
                if ':' in error_str:
                    mensaje_usuario = error_str.split(':', 1)[-1].strip()
            elif 'does not exist' in error_str.lower():
                mensaje_usuario = 'La devolución no existe o el estado no es válido'
            elif 'Duplicate entry' in error_str:
                mensaje_usuario = 'Ya existe un registro con estos datos'
            
            return jsonify({
                'success': False,
                'error': mensaje_usuario,
                'mensaje': mensaje_usuario
            }), 500
        
    except Exception as e:
        import traceback
        error_str = str(e)
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        mensaje_error = 'Error al actualizar el estado de la devolución'
        if 'Error:' in error_str:
            mensaje_error = error_str.split('Error:')[-1].strip()
        
        return jsonify({
            'success': False,
            'error': mensaje_error,
            'mensaje': mensaje_error
        }), 500

@app.route('/api/ventas/devoluciones/ver/<int:id_devolucion>', methods=['GET'])
@login_requerido
@requiere_rol('Vendedor')
def api_ventas_ver_devolucion(id_devolucion):
    """Endpoint para obtener detalles completos de una devolución para vendedores usando SP admin_devolucion_detalles - SOLO SP, NO SQL EMBEBIDO"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener información de la devolución usando SP admin_devolucion_detalles - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('admin_devolucion_detalles', [id_devolucion])
        devolucion_info = cursor.fetchone()
        
        # Si no hay devolución, consumir resultados y retornar error
        if not devolucion_info:
            # Consumir todos los resultados del SP
            while cursor.nextset():
                pass
            cursor.close()
            return jsonify({'error': 'Devolución no encontrada'}), 404
        
        # Obtener el segundo resultado set (detalles de productos devueltos)
        detalles_productos = []
        if cursor.nextset():
            detalles_productos = cursor.fetchall()
        
        # Consumir todos los resultados restantes del SP
        while cursor.nextset():
            pass
        
        cursor.close()
        
        # Formatear respuesta
        devolucion_dict = {
            'id_devolucion': devolucion_info.get('id_devolucion'),
            'id_pedido': devolucion_info.get('id_pedido'),
            'fecha_devolucion': devolucion_info.get('fecha_devolucion').strftime('%Y-%m-%d') if devolucion_info.get('fecha_devolucion') else None,
            'fecha_pedido': devolucion_info.get('fecha_pedido').strftime('%Y-%m-%d') if devolucion_info.get('fecha_pedido') else None,
            'total_pedido': float(devolucion_info.get('total_pedido', 0) or 0),
            'nombre_cliente': devolucion_info.get('nombre_cliente'),
            'email_cliente': devolucion_info.get('email_cliente'),
            'estado_devolucion': devolucion_info.get('estado_devolucion'),
            'tipo_devolucion': devolucion_info.get('tipo_devolucion'),
            'cantidad_productos': int(devolucion_info.get('cantidad_productos', 0) or 0),
            'productos': [
                {
                    'id_devolucion_detalle': item.get('id_devolucion_detalle'),
                    'id_producto': item.get('id_producto'),
                    'nombre_producto': item.get('nombre_producto'),
                    'sku': item.get('sku'),
                    'cantidad_devolucion': int(item.get('cantidad_devolucion', 0) or 0),
                    'precio_unitario': float(item.get('precio_unitario', 0) or 0),
                    'subtotal_devolucion': float(item.get('subtotal_devolucion', 0) or 0),
                    'tipo_devolucion': item.get('tipo_devolucion'),
                    'motivo_devolucion': item.get('motivo_devolucion'),
                    'reembolso': None  # Los vendedores no necesitan ver información de reembolsos
                }
                for item in detalles_productos
            ]
        }
        
        return jsonify(devolucion_dict)
    except Exception as e:
        import traceback
        print(f"Error obteniendo detalles de devolución: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': 'Error al obtener los detalles de la devolución'}), 500

@app.route('/api/admin/devoluciones/ver/<int:id_devolucion>', methods=['GET'])
@login_requerido
@requiere_rol('Admin', 'Inventarios', 'Gestor de Sucursal')
def api_ver_devolucion(id_devolucion):
    """Endpoint para obtener detalles completos de una devolución usando SP admin_devolucion_detalles - SOLO SP, NO SQL EMBEBIDO"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener información de la devolución usando SP admin_devolucion_detalles - SOLO SP, NO SQL EMBEBIDO
        cursor.callproc('admin_devolucion_detalles', [id_devolucion])
        devolucion_info = cursor.fetchone()
        
        # Si no hay devolución, consumir resultados y retornar error
        if not devolucion_info:
            # Consumir todos los resultados del SP
            while cursor.nextset():
                pass
            cursor.close()
            return jsonify({'error': 'Devolución no encontrada'}), 404
        
        # Obtener el segundo resultado set (detalles de productos devueltos)
        detalles_productos = []
        if cursor.nextset():
            detalles_productos = cursor.fetchall()
        
        # Consumir todos los resultados restantes del SP
        while cursor.nextset():
            pass
        
        cursor.close()
        
        # Formatear respuesta
        devolucion_dict = {
            'id_devolucion': devolucion_info.get('id_devolucion'),
            'id_pedido': devolucion_info.get('id_pedido'),
            'fecha_devolucion': devolucion_info.get('fecha_devolucion').strftime('%Y-%m-%d') if devolucion_info.get('fecha_devolucion') else None,
            'fecha_pedido': devolucion_info.get('fecha_pedido').strftime('%Y-%m-%d') if devolucion_info.get('fecha_pedido') else None,
            'total_pedido': float(devolucion_info.get('total_pedido', 0) or 0),
            'nombre_cliente': devolucion_info.get('nombre_cliente'),
            'email_cliente': devolucion_info.get('email_cliente'),
            'estado_devolucion': devolucion_info.get('estado_devolucion'),
            'tipo_devolucion': devolucion_info.get('tipo_devolucion'),
            'cantidad_productos': int(devolucion_info.get('cantidad_productos', 0) or 0),
            'productos': [
                {
                    'id_devolucion_detalle': item.get('id_devolucion_detalle'),
                    'id_producto': item.get('id_producto'),
                    'nombre_producto': item.get('nombre_producto'),
                    'sku': item.get('sku'),
                    'cantidad_devolucion': int(item.get('cantidad_devolucion', 0) or 0),
                    'precio_unitario': float(item.get('precio_unitario', 0) or 0),
                    'subtotal_devolucion': float(item.get('subtotal_devolucion', 0) or 0),
                    'tipo_devolucion': item.get('tipo_devolucion'),
                    'clasificacion_reembolso': item.get('clasificacion_reembolso'),
                    'motivo_devolucion': item.get('motivo_devolucion'),
                    'estado_devolucion': item.get('estado_devolucion'),
                    'reembolso': {
                        'id_reembolso': item.get('id_reembolso'),
                        'monto_reembolso': float(item.get('monto_reembolso', 0) or 0) if item.get('monto_reembolso') else None,
                        'fecha_reembolso': item.get('fecha_reembolso').strftime('%Y-%m-%d') if item.get('fecha_reembolso') else None,
                        'metodo_pago': item.get('metodo_pago')
                    } if item.get('id_reembolso') else None
                }
                for item in detalles_productos
            ]
        }
        
        return jsonify(devolucion_dict)
    except Exception as e:
        import traceback
        error_msg = f"Error obteniendo detalles de devolución: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)
        return jsonify({'error': 'Error al obtener los detalles de la devolución'}), 500

# ==================== RUTAS PARA CLIENTE ====================# Ruta de prueba simple para verificar que las rutas funcionan
@app.route('/cliente/test')
def cliente_test():
    """Ruta de prueba sin decoradores"""    
    return jsonify({'status': 'ok', 'message': 'Ruta /cliente/test funciona correctamente'})

@app.route('/cliente')
@login_requerido
def cliente_dashboard():
    """Dashboard del cliente - muestra el catálogo con navegación"""
    # Verificar que el usuario tenga sesión activa
    if 'user_id' not in session:        
        flash("Debes iniciar sesión para acceder a esta sección", "warning")
        return redirect(url_for("login"))
    
    categoria_seleccionada = request.args.get('categoria', '')
    
    try:
        import MySQLdb.cursors
        # Usar DictCursor para acceder a los campos por nombre en el template
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener todas las categorías activas usando SP categoriasActivas
        cursor.callproc('categoriasActivas', [])
        categorias = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener productos activos usando SP productosCatalogo
        categoria_param = categoria_seleccionada if categoria_seleccionada else None
        cursor.callproc('productosCatalogo', [categoria_param])
        productos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
    except Exception as e:
        import traceback        
        print(traceback.format_exc())
        productos = []
        categorias = []
    
    try:
        return render_template('cliente_dashboard.html', productos=productos, categorias=categorias, categoria_seleccionada=categoria_seleccionada)
    except Exception as e:
        import traceback        
        print(traceback.format_exc())
        # Fallback a catálogo público si hay error
        return redirect(url_for('catalogo'))

@app.route('/cliente/pedidos')
@login_requerido
def cliente_pedidos():
    """Vista de pedidos del cliente"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('cliente_pedidos_lista', [session.get('user_id')])
        pedidos = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('cliente_pedidos.html', pedidos=pedidos)
    except Exception as e:
        import traceback
        print(f"Error cargando pedidos del cliente: {str(e)}\n{traceback.format_exc()}")
        return render_template('cliente_pedidos.html', pedidos=[])

@app.route('/cliente/facturas')
@login_requerido
def cliente_facturas():
    """Vista de facturas del cliente"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('cliente_facturas_lista', [session.get('user_id')])
        facturas = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('cliente_facturas.html', facturas=facturas)
    except Exception as e:
        import traceback
        print(f"Error cargando facturas del cliente: {str(e)}\n{traceback.format_exc()}")
        return render_template('cliente_facturas.html', facturas=[])

@app.route('/api/cliente/facturas/crear', methods=['POST'])
@login_requerido
def api_cliente_crear_factura():
    """Endpoint para crear factura desde el cliente"""
    try:
        data = request.get_json()
        id_pedido = data.get('id_pedido')
        
        if not id_pedido:
            return jsonify({'success': False, 'error': 'ID de pedido requerido'}), 400

        # ===============================
        # 1. Verificar que el pedido exista (y obtener su estado)
        # ===============================
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sp_pedido_estado_obtener', (id_pedido,))
        pedido = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()

        if not pedido:
            return jsonify({
                'success': False,
                'error': 'Pedido no encontrado'
            }), 404

        # ===============================
        # 2. Verificar si ya tiene factura
        # ===============================
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sp_factura_verificar_existente', (id_pedido,))
        factura_existente = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()

        if factura_existente:
            return jsonify({'success': False, 'error': 'El pedido ya tiene una factura registrada'}), 400

        # ===============================
        # 3. Verificar que el pedido tenga detalles
        # ===============================
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sp_pedido_verificar_detalles', (id_pedido,))
        detalles = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()

        if not detalles or detalles.get('total_detalles', 0) == 0:
            return jsonify({'success': False, 'error': 'El pedido no tiene productos asociados'}), 400

        # ===============================
        # 4. Verificar que existe la empresa
        # ===============================
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sp_empresa_obtener_por_nombre', ('Auralisse Joyeria',))
        empresa = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()

        if not empresa or not empresa.get('id_empresa'):
            return jsonify({
                'success': False,
                'error': 'No se encontró la empresa "Auralisse Joyeria" en el sistema. Contacte al administrador.'
            }), 500

        # ===============================
        # 5. Verificar subtotal válido
        # ===============================
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sp_pedido_subtotal_calcular', (id_pedido,))
        subtotal_check = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()

        if not subtotal_check or subtotal_check.get('subtotal', 0) <= 0:
            return jsonify({'success': False, 'error': 'El pedido no tiene productos válidos o el total es cero'}), 400

        # ===============================
        # 6. Crear la factura (pedidoFacturar)
        # ===============================
        try:
            cursor = mysql.connection.cursor()
            cursor.callproc('pedidoFacturar', (id_pedido,))
            while cursor.nextset():
                pass
            cursor.close()
        except Exception as sp_error:
            # Si el SP truena, revertimos
            mysql.connection.rollback()
            error_msg = str(sp_error)
            if 'El pedido ya tiene una factura registrada' in error_msg:
                return jsonify({'success': False, 'error': 'El pedido ya tiene una factura registrada'}), 400
            elif 'El pedido no existe' in error_msg:
                return jsonify({'success': False, 'error': 'El pedido no existe'}), 404
            elif 'No se encontró la empresa Auralisse Joyeria' in error_msg:
                return jsonify({'success': False, 'error': 'No se encontró la empresa "Auralisse Joyeria" en el sistema. Contacte al administrador.'}), 500
            else:
                return jsonify({'success': False, 'error': f'Error en el stored procedure: {error_msg}'}), 500

        # ===============================
        # 7. Obtener la factura creada
        # ===============================
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sp_factura_obtener_por_pedido', (id_pedido,))
        factura = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()

        # Commit final
        mysql.connection.commit()

        if factura:
            return jsonify({
                'success': True,
                'mensaje': 'Factura creada exitosamente',
                'id_factura': factura['id_factura'],
                'folio': factura['folio']
            })
        else:
            return jsonify({
                'success': False,
                'error': 'No se pudo crear la factura. El stored procedure no generó la factura.'
            }), 500

    except Exception as e:
        import traceback
        print(f"Error creando factura: {str(e)}\n{traceback.format_exc()}", flush=True)
        try:
            mysql.connection.rollback()
        except Exception:
            # si ya estaba desincronizada la conexión, evitamos que truene aquí otra vez
            pass
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/cliente/devoluciones')
@login_requerido
def cliente_devoluciones():
    """Vista de devoluciones del cliente"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('cliente_devoluciones_lista', [session.get('user_id')])
        devoluciones = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return render_template('cliente_devoluciones.html', devoluciones=devoluciones)
    except Exception as e:
        import traceback
        print(f"Error cargando devoluciones del cliente: {str(e)}\n{traceback.format_exc()}")
        return render_template('cliente_devoluciones.html', devoluciones=[])

@app.route('/cliente/devoluciones/crear')
@login_requerido
def cliente_crear_devolucion():
    """Vista para crear devolución"""
    try:
        cursor = mysql.connection.cursor()
        
        # Obtener pedidos disponibles para devolución
        cursor.callproc('cliente_pedidos_disponibles_devolucion', [session.get('user_id')])
        pedidos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener tipos de devolución usando SP
        cursor.callproc('sp_tipos_devolucion_lista', [])
        tipos_devolucion = cursor.fetchall()
        while cursor.nextset():
            pass
        
        # Obtener motivos de devolución usando SP
        cursor.callproc('sp_motivos_devolucion_lista', [])
        motivos_devolucion = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        return render_template('cliente_crear_devolucion.html', pedidos=pedidos, tipos_devolucion=tipos_devolucion, motivos_devolucion=motivos_devolucion)
    except Exception as e:
        import traceback
        print(f"Error cargando datos para crear devolución: {str(e)}\n{traceback.format_exc()}")
        return render_template('cliente_crear_devolucion.html', pedidos=[], tipos_devolucion=[], motivos_devolucion=[])

@app.route('/api/cliente/devoluciones/pedido/<int:id_pedido>/productos')
@login_requerido
def api_cliente_obtener_productos_pedido(id_pedido):
    """Obtener productos de un pedido para devolución (solo del cliente autenticado)"""
    try:
        cursor = mysql.connection.cursor()
        cursor.callproc('cliente_pedido_detalles', [id_pedido, session.get('user_id')])
        productos = cursor.fetchall()
        while cursor.nextset():
            pass
        cursor.close()
        
        return jsonify(productos)
    except Exception as e:
        import traceback
        print(f"Error obteniendo productos del pedido: {str(e)}\n{traceback.format_exc()}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/cliente/devoluciones/crear', methods=['POST'])
@login_requerido
def api_cliente_crear_devolucion():
    """Endpoint para crear devolución desde el cliente"""
    try:
        data = request.get_json()
        id_pedido = data.get('id_pedido')
        productos = data.get('productos', [])
        
        if not id_pedido:
            return jsonify({'success': False, 'error': 'El ID del pedido es requerido'}), 400
        
        if not productos or len(productos) == 0:
            return jsonify({'success': False, 'error': 'Debe seleccionar al menos un producto'}), 400
        
        cursor = mysql.connection.cursor()
        
        # Verificar que el pedido pertenece al cliente
        cursor.callproc('sp_pedido_verificar_cliente', [id_pedido, session.get('user_id')])
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not resultado:
            cursor.close()
            return jsonify({'success': False, 'error': 'Pedido no encontrado o no pertenece al cliente'}), 403
        
        # Crear devolución usando el SP existente
        # El SP devolucionCrear requiere: id_pedido, productos (JSON)
        # El SP espera: id_producto, cantidad, motivo, id_tipo_devolucion
        # El frontend ya envía el formato correcto
        productos_json = json.dumps(productos)        # Llamar al SP devolucionCrear (solo 2 parámetros: id_pedido y JSON)
        try:
            cursor.callproc('devolucionCrear', [id_pedido, productos_json])
            resultado = cursor.fetchone()
            
            while cursor.nextset():
                pass
            
            mysql.connection.commit()
            cursor.close()
            
            # El SP puede retornar el id_devolucion o un mensaje
            if resultado:
                if isinstance(resultado, dict):
                    id_devolucion = resultado.get('id_devolucion') or resultado.get('Mensaje')
                else:
                    id_devolucion = resultado[0] if len(resultado) > 0 else None
            else:
                id_devolucion = None
            
            return jsonify({
                'success': True,
                'mensaje': 'Devolución creada exitosamente',
                'id_devolucion': id_devolucion
            })
        except Exception as sp_error:
            cursor.close()
            mysql.connection.rollback()
            error_msg = str(sp_error)            
            import traceback
            print(f"[TRACEBACK] {traceback.format_exc()}", flush=True)
            
            # Extraer mensaje del error del SP si es posible
            mensaje_usuario = 'Error al crear la devolución. Verifique los datos e intente nuevamente.'
            if 'ERROR' in error_msg or 'Error:' in error_msg:
                import re
                match = re.search(r'["\']([^"\']+)["\']', error_msg)
                if match:
                    mensaje_usuario = match.group(1)
            
            return jsonify({
                'success': False,
                'error': mensaje_usuario
            }), 500
        
    except Exception as e:
        import traceback
        error_str = str(e)
        print(f"Error creando devolución: {error_str}\n{traceback.format_exc()}")
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        mensaje_usuario = 'Error al crear la devolución. Verifique los datos e intente nuevamente.'
        
        if 'ERROR' in error_str:
            import re
            match = re.search(r'["\']([^"\']+)["\']', error_str)
            if match:
                mensaje_usuario = match.group(1)
        
        return jsonify({
            'success': False,
            'error': mensaje_usuario
        }), 500

@app.route('/cliente/pago/<int:id_factura>')
@login_requerido
def cliente_pago(id_factura):
    """Vista para simular pago de una factura"""
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Verificar que la factura pertenece al cliente
        cursor.callproc('sp_factura_verificar_cliente', [id_factura, session.get('user_id')])
        factura = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not factura:
            cursor.close()
            flash('Factura no encontrada', 'danger')
            return redirect(url_for('cliente_facturas'))
        
        # Obtener métodos de pago usando SP
        cursor.callproc('sp_metodos_pago_lista_nombre', [])
        metodos_pago = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        total_pagado = float(factura.get('total_pagado', 0) or 0)
        total_factura = float(factura.get('total', 0) or 0)
        pendiente = total_factura - total_pagado
        
        return render_template('cliente_pago.html', 
                             factura=factura, 
                             metodos_pago=metodos_pago,
                             total_pagado=total_pagado,
                             pendiente=pendiente)
    except Exception as e:
        import traceback
        print(f"Error cargando datos de pago: {str(e)}\n{traceback.format_exc()}")
        flash('Error al cargar los datos de pago', 'danger')
        return redirect(url_for('cliente_facturas'))

@app.route('/api/cliente/pago/registrar', methods=['POST'])
@login_requerido
def api_cliente_registrar_pago():
    """Endpoint para registrar pago desde el cliente"""
    try:
        data = request.get_json()
        id_factura = data.get('id_factura')
        importe = float(data.get('importe', 0))
        id_metodo_pago = data.get('id_metodo_pago')
        
        if not id_factura or not id_metodo_pago or importe <= 0:
            return jsonify({'success': False, 'error': 'Datos incompletos'}), 400
        
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Verificar que la factura pertenece al cliente
        cursor.callproc('sp_factura_info_cliente', [id_factura, session.get('user_id')])
        factura_data = cursor.fetchone()
        while cursor.nextset():
            pass
        if not factura_data:
            cursor.close()
            return jsonify({'success': False, 'error': 'Factura no encontrada'}), 403
        
        total_factura = float(factura_data.get('total', 0) or 0)
        total_pagado = float(factura_data.get('total_pagado', 0) or 0)
        pendiente = total_factura - total_pagado
        
        if importe > pendiente:
            cursor.close()
            return jsonify({'success': False, 'error': f'El importe no puede ser mayor al pendiente (${pendiente:.2f})'}), 400
        
        # Registrar pago usando el stored procedure cliente_pago_registrar
        try:
            cursor.callproc('cliente_pago_registrar', [
                id_factura,
                session.get('user_id'),
                importe,
                id_metodo_pago
            ])            # Obtener resultado del SP
            resultado = cursor.fetchone()
            while cursor.nextset():
                pass
            
            mysql.connection.commit()
            cursor.close()
            
            if resultado:
                # El resultado puede ser dict o tuple dependiendo del cursor
                if isinstance(resultado, dict):
                    return jsonify({
                        'success': True,
                        'mensaje': resultado.get('Mensaje', 'Pago registrado exitosamente'),
                        'estado': resultado.get('Estado'),
                        'total_pagado': float(resultado.get('Total_Pagado', 0)),
                        'pendiente': float(resultado.get('Pendiente', 0))
                    })
                else:
                    # Si es tupla, los índices son: Mensaje, Estado, Total_Pagado, Pendiente
                    return jsonify({
                        'success': True,
                        'mensaje': resultado[0] if len(resultado) > 0 else 'Pago registrado exitosamente',
                        'estado': resultado[1] if len(resultado) > 1 else None,
                        'total_pagado': float(resultado[2]) if len(resultado) > 2 else 0,
                        'pendiente': float(resultado[3]) if len(resultado) > 3 else 0
                    })
            else:
                return jsonify({
                    'success': True,
                    'mensaje': 'Pago registrado exitosamente'
                })
                
        except Exception as sp_error:
            cursor.close()
            mysql.connection.rollback()
            error_msg = str(sp_error)
            import traceback           
            print(f"[TRACEBACK] {traceback.format_exc()}", flush=True)
            
            # Extraer mensaje del error del SP
            if 'La factura no existe' in error_msg:
                return jsonify({'success': False, 'error': 'La factura no existe'}), 404
            elif 'no pertenece al cliente' in error_msg:
                return jsonify({'success': False, 'error': 'La factura no pertenece al cliente'}), 403
            elif 'no puede ser mayor al pendiente' in error_msg:
                return jsonify({'success': False, 'error': 'El importe excede el monto pendiente'}), 400
            elif 'debe ser mayor a cero' in error_msg:
                return jsonify({'success': False, 'error': 'El importe debe ser mayor a cero'}), 400
            else:
                return jsonify({
                    'success': False,
                    'error': f'Error al registrar el pago: {error_msg}'
                }), 500
        
    except Exception as e:
        import traceback
        print(f"Error registrando pago: {str(e)}\n{traceback.format_exc()}")
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        return jsonify({
            'success': False,
            'error': 'Error al registrar el pago'
        }), 500

@app.route('/cliente/perfil')
@login_requerido
def cliente_perfil():
    """Vista para ver y editar perfil del cliente"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('cliente_perfil_obtener', [session.get('user_id')])
        perfil = cursor.fetchone()
        while cursor.nextset():
            pass
        
        # Debug: verificar clasificación
        if perfil:
            print(f"[DEBUG] Perfil obtenido - nombre_clasificacion: {perfil.get('nombre_clasificacion')}, descuento_clasificacion: {perfil.get('descuento_clasificacion')}")
        
        # Obtener catálogos usando SP
        cursor.callproc('sp_generos_lista', [])
        generos = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.callproc('sp_clasificaciones_lista', [])
        clasificaciones = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.callproc('sp_estados_direcciones_lista', [])
        estados = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        return render_template('cliente_perfil.html', perfil=perfil, generos=generos, clasificaciones=clasificaciones, estados=estados)
    except Exception as e:
        import traceback
        print(f"Error cargando perfil: {str(e)}\n{traceback.format_exc()}")
        return render_template('cliente_perfil.html', perfil=None, generos=[], clasificaciones=[], estados=[])

@app.route('/api/cliente/perfil/actualizar', methods=['POST'])
@login_requerido
def api_cliente_actualizar_perfil():
    """Endpoint para actualizar perfil del cliente"""
    try:
        data = request.get_json()
        
        # Validar datos requeridos
        nombre_usuario = data.get('nombre_usuario', '').strip()
        nombre_primero = data.get('nombre_primero', '').strip()
        apellido_paterno = data.get('apellido_paterno', '').strip()
        calle_direccion = data.get('calle_direccion', '').strip()
        numero_direccion = data.get('numero_direccion', '').strip()
        codigo_postal = data.get('codigo_postal', '').strip()
        municipio = data.get('municipio', '').strip()
        id_estado = data.get('id_estado_direccion')
        
        if not nombre_usuario or not nombre_primero or not apellido_paterno:
            return jsonify({'success': False, 'error': 'Nombre de usuario, nombre y apellido paterno son requeridos'}), 400
        
        if not calle_direccion or not numero_direccion or not codigo_postal:
            return jsonify({'success': False, 'error': 'Dirección completa es requerida'}), 400
        
        if len(codigo_postal) != 5:
            return jsonify({'success': False, 'error': 'El código postal debe tener 5 dígitos'}), 400
        
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Preparar parámetros para el stored procedure (15 parámetros totales)
        params = [
            session.get('user_id'),
            nombre_usuario,
            nombre_primero,
            data.get('nombre_segundo', '') or '',
            apellido_paterno,
            data.get('apellido_materno', '') or '',
            data.get('rfc_usuario', '') or '',
            data.get('telefono', '') or '',
            data.get('correo', '') or '',
            data.get('id_genero'),
            calle_direccion,
            numero_direccion,
            codigo_postal,
            municipio or '',
            id_estado
        ]
        
        print(f"[DEBUG] Llamando cliente_perfil_actualizar con {len(params)} parámetros")
        print(f"[DEBUG] Parámetros: id_usuario={params[0]}, municipio={params[13]}, id_estado={params[14]}")
        
        cursor.callproc('cliente_perfil_actualizar', params)
        
        resultado = cursor.fetchone()
        while cursor.nextset():
            pass
        
        mysql.connection.commit()
        cursor.close()
        
        # Actualizar sesión
        session['username'] = nombre_usuario
        session['full_name'] = f"{nombre_primero} {apellido_paterno}"
        
        # Obtener mensaje del resultado (puede ser diccionario o tupla)
        mensaje = 'Perfil actualizado exitosamente'
        if resultado:
            if isinstance(resultado, dict):
                mensaje = resultado.get('mensaje', mensaje)
            else:
                mensaje = resultado[0] if len(resultado) > 0 else mensaje
        
        return jsonify({
            'success': True,
            'mensaje': mensaje
        })
        
    except Exception as e:
        import traceback
        error_str = str(e)
        print(f"Error actualizando perfil: {error_str}\n{traceback.format_exc()}")
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        mensaje_usuario = 'Error al actualizar el perfil'
        
        if 'ERROR' in error_str or 'Error' in error_str:
            import re
            match = re.search(r'["\']([^"\']+)["\']', error_str)
            if match:
                mensaje_usuario = match.group(1)
        
        return jsonify({
            'success': False,
            'error': mensaje_usuario
        }), 500

@app.route('/api/admin/clientes/<int:id_cliente>/completar-datos', methods=['POST'])
@login_requerido
@requiere_rol('Admin', 'Vendedor')
def api_admin_completar_datos_cliente(id_cliente):
    """Endpoint para que Admin/Vendedor complete datos faltantes de un cliente (RFC, dirección, teléfono)"""
    try:
        import MySQLdb.cursors
        data = request.get_json()
        
        # Obtener id_usuario del cliente usando SP
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sp_cliente_obtener_usuario', [id_cliente])
        cliente_data = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not cliente_data:
            cursor.close()
            return jsonify({'success': False, 'error': 'Cliente no encontrado'}), 404
        
        id_usuario = cliente_data['id_usuario']
        
        # Obtener datos actuales del usuario
        cursor.callproc('sp_usuario_datos_completos', [id_usuario])
        usuario_data = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()
        
        if not usuario_data:
            return jsonify({'success': False, 'error': 'Usuario no encontrado'}), 404
        
        # Usar datos proporcionados o mantener los existentes
        rfc_usuario = data.get('rfc_usuario', '').strip() or usuario_data.get('rfc_usuario') or ''
        telefono = data.get('telefono', '').strip() or usuario_data.get('telefono') or ''
        calle_direccion = data.get('calle_direccion', '').strip() or usuario_data.get('calle_direccion') or ''
        numero_direccion = data.get('numero_direccion', '').strip() or usuario_data.get('numero_direccion') or ''
        codigo_postal = data.get('codigo_postal', '').strip() or usuario_data.get('codigo_postal') or ''
        
        # Validaciones
        if not rfc_usuario:
            return jsonify({'success': False, 'error': 'El RFC es requerido'}), 400
        if len(rfc_usuario) > 13:
            return jsonify({'success': False, 'error': 'El RFC no puede tener más de 13 caracteres'}), 400
        if not telefono:
            return jsonify({'success': False, 'error': 'El teléfono es requerido'}), 400
        if not calle_direccion or not numero_direccion or not codigo_postal:
            return jsonify({'success': False, 'error': 'La dirección completa es requerida (calle, número y código postal)'}), 400
        if len(codigo_postal) != 5 or not codigo_postal.isdigit():
            return jsonify({'success': False, 'error': 'El código postal debe tener exactamente 5 dígitos numéricos'}), 400
        
        # Llamar al stored procedure para actualizar
        cursor2 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        try:
            cursor2.callproc('cliente_perfil_actualizar', [
                id_usuario,
                usuario_data.get('nombre_usuario', ''),
                usuario_data.get('nombre_primero', ''),
                usuario_data.get('nombre_segundo', '') or '',
                usuario_data.get('apellido_paterno', ''),
                usuario_data.get('apellido_materno', '') or '',
                rfc_usuario,
                telefono,
                usuario_data.get('correo', ''),
                usuario_data.get('id_genero'),
                calle_direccion,
                numero_direccion,
                codigo_postal
            ])
            
            resultado = cursor2.fetchone()
            
            while cursor2.nextset():
                pass
            
            mysql.connection.commit()
            cursor2.close()
            
            mensaje = 'Datos del cliente completados exitosamente'
            if resultado:
                if isinstance(resultado, dict):
                    mensaje = resultado.get('mensaje', mensaje)                
                elif isinstance(resultado, (list, tuple)) and len(resultado) > 0:
                    mensaje = resultado[0] if isinstance(resultado[0], str) else mensaje           
            return jsonify({
                'success': True,
                'mensaje': mensaje
            })
            
        except Exception as sp_error:
            cursor2.close()
            mysql.connection.rollback()
            error_str = str(sp_error)
            error_type = type(sp_error).__name__
            
            # Extraer mensaje específico del error
            mensaje_error = 'Error al completar datos del cliente'
            
            # Si es un error de MySQL/MariaDB, extraer el mensaje
            if hasattr(sp_error, 'args') and len(sp_error.args) > 0:
                error_msg = sp_error.args[0]
                if isinstance(error_msg, (int, str)):
                    if isinstance(error_msg, int) and error_msg == 0:
                        mensaje_error = 'Error al procesar la solicitud. Verifique que todos los campos estén completos.'
                    elif isinstance(error_msg, str):
                        if 'Error:' in error_msg:
                            mensaje_error = error_msg.split('Error:')[-1].strip()
                        elif len(error_msg) > 1:
                            mensaje_error = error_msg
            
            # Intentar extraer de la cadena de error
            if 'Error:' in error_str:
                mensaje_error = error_str.split('Error:')[-1].strip()
            elif 'SET MESSAGE_TEXT' in error_str:
                import re
                match = re.search(r"SET MESSAGE_TEXT = '([^']+)'", error_str)
                if match:
                    mensaje_error = match.group(1)
            elif error_str and error_str != '0' and len(error_str) > 1:
                mensaje_error = error_str
            
            # Si el mensaje sigue siendo genérico o "0", proporcionar uno más útil
            if mensaje_error == '0' or len(mensaje_error) <= 1:
                mensaje_error = 'Error al guardar los datos. Verifique que todos los campos estén completos y sean válidos (RFC máximo 13 caracteres, código postal 5 dígitos).'
            
            return jsonify({
                'success': False,
                'error': mensaje_error
            }), 400
        
    except Exception as e:
        import traceback
        error_str = str(e)
        print(f"Error completando datos del cliente: {error_str}\n{traceback.format_exc()}")
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        # Extraer mensaje específico del error
        mensaje_error = 'Error al completar datos del cliente'
        
        # Si es un error de MySQL/MariaDB, extraer el mensaje
        if hasattr(e, 'args') and len(e.args) > 0:
            error_msg = e.args[0]
            if isinstance(error_msg, (int, str)):
                if isinstance(error_msg, int) and error_msg == 0:
                    mensaje_error = 'Error al procesar la solicitud. Verifique que todos los campos estén completos y sean válidos.'
                elif isinstance(error_msg, str):
                    if 'Error:' in error_msg:
                        mensaje_error = error_msg.split('Error:')[-1].strip()
                    elif len(error_msg) > 1:
                        mensaje_error = error_msg
        
        # Intentar extraer de la cadena de error
        if 'Error:' in error_str:
            mensaje_error = error_str.split('Error:')[-1].strip()
        elif 'SET MESSAGE_TEXT' in error_str:
            import re
            match = re.search(r"SET MESSAGE_TEXT = '([^']+)'", error_str)
            if match:
                mensaje_error = match.group(1)
        elif error_str and error_str != '0' and len(error_str) > 1:
            mensaje_error = error_str
        
        # Si el mensaje sigue siendo genérico o "0", proporcionar uno más útil
        if mensaje_error == '0' or len(mensaje_error) <= 1:
            mensaje_error = 'Error al guardar los datos. Verifique que todos los campos estén completos y sean válidos (RFC máximo 13 caracteres, código postal 5 dígitos, teléfono requerido).'
        
        return jsonify({
            'success': False,
            'error': mensaje_error
        }), 500

@app.route('/api/admin/clientes/<int:id_cliente>/datos', methods=['GET'])
@login_requerido
@requiere_rol('Admin', 'Vendedor')
def api_admin_obtener_datos_cliente(id_cliente):
    """Endpoint para obtener datos de un cliente (para completar información faltante)"""
    try:
        import MySQLdb.cursors
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener id_usuario del cliente usando SP
        cursor.callproc('sp_cliente_obtener_usuario', [id_cliente])
        cliente_data = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not cliente_data:
            cursor.close()
            return jsonify({'success': False, 'error': 'Cliente no encontrado'}), 404
        
        id_usuario = cliente_data['id_usuario']
        
        # Obtener datos del usuario
        cursor.execute("""
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
                cp.codigo_postal
            FROM Usuarios u
            LEFT JOIN Direcciones d ON u.id_direccion = d.id_direccion
            LEFT JOIN Codigos_Postales cp ON d.id_cp = cp.id_cp
            WHERE u.id_usuario = %s
        """, (id_usuario,))
        usuario_data = cursor.fetchone()
        cursor.close()
        
        if not usuario_data:
            return jsonify({'success': False, 'error': 'Usuario no encontrado'}), 404
        
        return jsonify({
            'success': True,
            'cliente': usuario_data
        })
        
    except Exception as e:
        import traceback
        print(f"Error obteniendo datos del cliente: {str(e)}\n{traceback.format_exc()}")
        return jsonify({
            'success': False,
            'error': f'Error al obtener datos del cliente: {str(e)}'
        }), 500

@app.route('/ventas/clientes/<int:id_cliente>/completar-datos')
@login_requerido
@requiere_rol('Admin', 'Vendedor')
def ventas_completar_datos_cliente(id_cliente):
    """Página para completar datos faltantes del cliente antes de crear pedido"""
    import MySQLdb.cursors
    
    try:
        # Obtener datos del cliente
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        # Obtener id_usuario del cliente usando SP
        cursor.callproc('sp_cliente_obtener_usuario', [id_cliente])
        cliente_data = cursor.fetchone()
        while cursor.nextset():
            pass
        
        if not cliente_data:
            cursor.close()
            return render_template('error.html', mensaje='Cliente no encontrado'), 404
        
        id_usuario = cliente_data['id_usuario']
        
        # Obtener datos del usuario
        cursor.callproc('sp_usuario_datos_completos', [id_usuario])
        usuario_data = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()
        
        if not usuario_data:
            return render_template('error.html', mensaje='Usuario no encontrado'), 404
        
        # Obtener nombre completo del cliente
        nombre_completo = f"{usuario_data.get('nombre_primero', '')} {usuario_data.get('apellido_paterno', '')}".strip()
        
        user = {
            "full_name": session.get("full_name", "Admin"),
            "role": session.get("role", "Admin")
        }
        
        return render_template(
            'ventas_completar_datos_cliente.html',
            cliente=usuario_data,
            id_cliente=id_cliente,
            nombre_completo=nombre_completo,
            user=user
        )
        
    except Exception as e:
        import traceback
        print(f"Error cargando página completar datos: {str(e)}\n{traceback.format_exc()}")
        return render_template('error.html', mensaje='Error al cargar datos del cliente'), 500

@app.route('/cliente/completar-datos')
@login_requerido
def cliente_completar_datos():
    """Página para que el cliente complete sus datos faltantes (RFC, dirección, teléfono)"""
    import MySQLdb.cursors
    try:
        id_usuario = session.get('user_id')
        if not id_usuario:
            flash('Debe iniciar sesión para acceder a esta página', 'warning')
            return redirect(url_for('login'))
        
        # Obtener datos del usuario
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
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
            WHERE u.id_usuario = %s
        """, (id_usuario,))
        usuario_data = cursor.fetchone()
        
        # Obtener lista de estados para el dropdown usando SP
        cursor.callproc('sp_estados_direcciones_lista', [])
        estados = cursor.fetchall()
        while cursor.nextset():
            pass
        
        cursor.close()
        
        if not usuario_data:
            return render_template('error.html', mensaje='Usuario no encontrado'), 404
        
        nombre_completo = f"{usuario_data.get('nombre_primero', '')} {usuario_data.get('apellido_paterno', '')}".strip()
        
        return render_template('cliente_completar_datos.html', 
                            cliente=usuario_data, 
                            nombre_completo=nombre_completo,
                            estados=estados)
    except Exception as e:
        import traceback
        print(f"Error cargando página completar datos cliente: {str(e)}\n{traceback.format_exc()}")
        return render_template('error.html', mensaje='Error al cargar la página'), 500

@app.route('/api/cliente/completar-datos', methods=['POST'])
@login_requerido
def api_cliente_completar_datos():
    """Endpoint para que el cliente complete sus propios datos faltantes (RFC, dirección, teléfono)"""
    try:
        import MySQLdb.cursors
        data = request.get_json()
        id_usuario = session.get('user_id')

        if not id_usuario:
            return jsonify({'success': False, 'error': 'Debe iniciar sesión'}), 401

        # Obtener datos actuales del usuario
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
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
                cp.codigo_postal,
                d.id_estado_direccion
            FROM Usuarios u
            LEFT JOIN Direcciones d ON u.id_direccion = d.id_direccion
            LEFT JOIN Codigos_Postales cp ON d.id_cp = cp.id_cp
            WHERE u.id_usuario = %s
        """, (id_usuario,))
        usuario_data = cursor.fetchone()
        cursor.close()

        if not usuario_data:
            return jsonify({'success': False, 'error': 'Usuario no encontrado'}), 404

        # Usar datos proporcionados o mantener los existentes
        rfc_usuario = data.get('rfc_usuario', '').strip() or usuario_data.get('rfc_usuario') or ''
        telefono = data.get('telefono', '').strip() or usuario_data.get('telefono') or ''
        calle_direccion = data.get('calle_direccion', '').strip() or usuario_data.get('calle_direccion') or ''
        numero_direccion = data.get('numero_direccion', '').strip() or usuario_data.get('numero_direccion') or ''
        codigo_postal = data.get('codigo_postal', '').strip() or usuario_data.get('codigo_postal') or ''
        municipio = data.get('municipio', '').strip() or ''
        id_estado = data.get('id_estado')

        if id_estado:
            try:
                id_estado = int(id_estado)
            except (ValueError, TypeError):
                id_estado = None
        else:
            id_estado = usuario_data.get('id_estado_direccion')

        # Validaciones
        if not rfc_usuario:
            return jsonify({'success': False, 'error': 'El RFC es requerido'}), 400
        if len(rfc_usuario) > 13:
            return jsonify({'success': False, 'error': 'El RFC no puede tener más de 13 caracteres'}), 400
        if not telefono:
            return jsonify({'success': False, 'error': 'El teléfono es requerido'}), 400
        if not calle_direccion or not numero_direccion or not codigo_postal:
            return jsonify({'success': False, 'error': 'La dirección completa es requerida (calle, número y código postal)'}), 400
        if len(codigo_postal) != 5 or not codigo_postal.isdigit():
            return jsonify({'success': False, 'error': 'El código postal debe tener exactamente 5 dígitos numéricos'}), 400
        if not municipio:
            return jsonify({'success': False, 'error': 'El municipio es requerido'}), 400
        if not id_estado:
            return jsonify({'success': False, 'error': 'El estado es requerido'}), 400

        # Llamar al stored procedure para actualizar
        cursor2 = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        try:
            params = [
                id_usuario,
                usuario_data.get('nombre_usuario'),
                usuario_data.get('nombre_primero'),
                usuario_data.get('nombre_segundo') or '',
                usuario_data.get('apellido_paterno'),
                usuario_data.get('apellido_materno') or '',
                rfc_usuario,
                telefono,
                usuario_data.get('correo') or '',
                usuario_data.get('id_genero'),
                calle_direccion,
                numero_direccion,
                codigo_postal,
                municipio,
                id_estado
            ]

            print(f"[DEBUG] Llamando cliente_perfil_actualizar con {len(params)} parámetros")
            print(f"[DEBUG] Parámetros: id_usuario={id_usuario}, municipio={municipio}, id_estado={id_estado}")

            cursor2.callproc('cliente_perfil_actualizar', params)
            resultado = cursor2.fetchone()
            while cursor2.nextset():
                pass
            mysql.connection.commit()
            cursor2.close()

            print(f"[DEBUG] Stored procedure ejecutado exitosamente")

            return jsonify({
                'success': True,
                'mensaje': 'Datos completados exitosamente'
            })
        except Exception as sp_error:
            import traceback as tb
            error_str = str(sp_error)
            error_trace = tb.format_exc()
            print(f"[ERROR] Error en stored procedure cliente_perfil_actualizar:")
            print(f"[ERROR] Mensaje: {error_str}")
            print(f"[ERROR] Traceback:\n{error_trace}")

            try:
                cursor2.close()
            except:
                pass
            try:
                mysql.connection.rollback()
            except:
                pass

            mensaje_error = 'Error al guardar los datos'
            if 'Error:' in error_str:
                mensaje_error = error_str.split('Error:')[-1].strip()

            return jsonify({
                'success': False,
                'error': mensaje_error
            }), 500

    except Exception as e:
        import traceback as tb
        error_str = str(e)
        error_trace = tb.format_exc()
        print(f"[ERROR] Error general en api_cliente_completar_datos:")
        print(f"[ERROR] Mensaje: {error_str}")
        print(f"[ERROR] Traceback:\n{error_trace}")

        return jsonify({
            'success': False,
            'error': f'Error al completar datos: {error_str}'
        }), 500

@app.route('/api/cliente/contrasena/actualizar', methods=['POST'])
@login_requerido
def api_cliente_actualizar_contrasena():
    """Endpoint para actualizar contraseña del cliente"""
    try:
        data = request.get_json()
        contrasena_actual = data.get('contrasena_actual', '').strip()
        contrasena_nueva = data.get('contrasena_nueva', '').strip()
        contrasena_nueva_confirmar = data.get('contrasena_nueva_confirmar', '').strip()
        
        # Validaciones básicas
        if not contrasena_actual or not contrasena_nueva:
            return jsonify({'success': False, 'error': 'Contraseña actual y nueva son requeridas'}), 400
        
        if contrasena_nueva != contrasena_nueva_confirmar:
            return jsonify({'success': False, 'error': 'Las contraseñas nuevas no coinciden'}), 400
        
        if len(contrasena_nueva) < 6:
            return jsonify({'success': False, 'error': 'La contraseña debe tener al menos 6 caracteres'}), 400
        
        user_id = session.get('user_id')
        
        # 1. Obtener contraseña actual desde la BD usando SP
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.callproc('sp_usuario_obtener_contrasena', [user_id])
        usuario = cursor.fetchone()
        while cursor.nextset():
            pass
        cursor.close()
        
        if not usuario:
            return jsonify({'success': False, 'error': 'Usuario no encontrado'}), 404
        
        # 2. Verificar contraseña actual con Argon2
        try:
            ph.verify(usuario['contrasena'], contrasena_actual)
        except VerifyMismatchError:
            return jsonify({'success': False, 'error': 'Contraseña actual incorrecta'}), 400
        
        # 3. Hashear nueva contraseña
        hash_nueva = ph.hash(contrasena_nueva)
        
        # 4. Actualizar contraseña con el SP (SOLO 2 PARÁMETROS)
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        
        try:
            cursor.callproc('cliente_contrasena_actualizar', [
                user_id,      # p_id_usuario
                hash_nueva    # p_contrasena_nueva (ya hasheada)
            ])
            
            # Obtener resultado del SP (el SELECT 'Contraseña actualizada exitosamente')
            resultado = cursor.fetchone()
            while cursor.nextset():
                pass
            
            mysql.connection.commit()
            cursor.close()
            
            mensaje = resultado.get('mensaje', 'Contraseña actualizada exitosamente') if resultado else 'Contraseña actualizada exitosamente'
            
            return jsonify({
                'success': True,
                'mensaje': mensaje
            })
        
        except Exception as sp_error:
            import traceback as tb
            cursor.close()
            mysql.connection.rollback()
            
            error_msg = str(sp_error)
            print(f"[TRACEBACK] {tb.format_exc()}", flush=True)
            
            # Si algún día tu SP lanza SIGNAL con mensajes específicos, los puedes mapear aquí:
            if 'Usuario no encontrado' in error_msg:
                return jsonify({'success': False, 'error': 'Usuario no encontrado'}), 404
            else:
                return jsonify({
                    'success': False,
                    'error': f'Error al actualizar la contraseña: {error_msg}'
                }), 500
        
    except Exception as e:
        import traceback as tb
        error_str = str(e)
        print(f"Error actualizando contraseña: {error_str}\n{tb.format_exc()}")
        
        try:
            mysql.connection.rollback()
        except:
            pass
        
        mensaje_usuario = 'Error al actualizar la contraseña'
        
        # Si el error trae mensaje entre comillas, lo extraemos
        if 'ERROR' in error_str or 'Error' in error_str:
            import re
            match = re.search(r'["\']([^"\']+)["\']', error_str)
            if match:
                mensaje_usuario = match.group(1)
        
        return jsonify({
            'success': False,
            'error': mensaje_usuario
        }), 500

# ==================== MANEJO DE ERRORES ====================

@app.errorhandler(403)
def forbidden(error):
    return render_template('403.html'), 403

@app.errorhandler(404)
def not_found(error):
    # Log para debug - forzar flush para asegurar que se muestre
    import sys

    # Si es una ruta API, devolver JSON en lugar de HTML
    if request.path.startswith('/api/'):
        return jsonify({
            'success': False,
            'error': 'Ruta no encontrada',
            'path': request.path
        }), 404

    rutas_encontradas = False

    # Mostrar rutas relacionadas a "cliente" para debug
    for rule in app.url_map.iter_rules():
        if '/cliente' in rule.rule and not rule.rule.startswith('/api'):
            print(f"  - {rule.rule} -> {rule.endpoint}", flush=True)
            rutas_encontradas = True

    if not rutas_encontradas:
        return render_template('404.html'), 404

    # Si sí encontró rutas, pero no coincide ninguna → también 404
    return render_template('404.html'), 404

@app.errorhandler(500)
def internal_error(error):
    # Si es una ruta API, devolver JSON en lugar de HTML
    if request.path.startswith('/api/'):
        import traceback
        error_msg = str(error)        
        print(traceback.format_exc(), flush=True)
        return jsonify({
            'success': False,
            'error': 'Error interno del servidor',
            'message': error_msg
        }), 500
    return render_template('500.html'), 500

# ==================== INICIO DE LA APLICACIÓN ====================

if __name__ == '__main__':   
    rutas_cliente_count = 0
    for rule in app.url_map.iter_rules():
        if '/cliente' in rule.rule and not rule.rule.startswith('/api'):
            print(f"  [OK] {rule.rule} -> {rule.endpoint}", flush=True)
            rutas_cliente_count += 1    
            app.run(debug=True, host='0.0.0.0', port=5000, use_reloader=False)
