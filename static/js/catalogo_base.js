// Funcionalidad del Carrito Sidebar
(function () {
    const cartSidebar = document.getElementById('cartSidebar');
    const cartOverlay = document.getElementById('cartOverlay');
    const cartIcon = document.getElementById('cartIcon');
    const closeCart = document.getElementById('closeCart');
    const cartItems = document.getElementById('cartItems');
    const cartTotal = document.getElementById('cartTotal');
    const btnPagar = document.getElementById('btnPagar');
    const cartBadge = document.getElementById('cartBadge');

    // Abrir carrito
    function abrirCarrito() {
        cartSidebar.classList.add('active');
        cartOverlay.classList.add('active');
        document.body.style.overflow = 'hidden';
        cargarCarrito();
    }

    // Cerrar carrito
    function cerrarCarrito() {
        cartSidebar.classList.remove('active');
        cartOverlay.classList.remove('active');
        document.body.style.overflow = '';
    }

    // Event listeners
    if (cartIcon) {
        cartIcon.addEventListener('click', function (e) {
            e.preventDefault();
            abrirCarrito();
        });
    }

    if (closeCart) {
        closeCart.addEventListener('click', cerrarCarrito);
    }

    if (cartOverlay) {
        cartOverlay.addEventListener('click', cerrarCarrito);
    }

    // Cargar productos del carrito
    function cargarCarrito() {
        fetch('/api/carrito/obtener')
            .then(response => response.json())
            .then(data => {
                if (data.carrito && data.carrito.length > 0) {
                    renderizarCarrito(data.carrito, data.total);
                    actualizarBadgeCarrito(data.total_items);
                    btnPagar.disabled = false;
                } else {
                    cartItems.innerHTML = `
                        <div class="cart-empty">
                            <i class="bi bi-cart-x"></i>
                            <p>Tu carrito está vacío</p>
                        </div>
                    `;
                    cartTotal.textContent = '$0.00';
                    actualizarBadgeCarrito(0);
                    btnPagar.disabled = true;
                }
            })
            .catch(error => {
                console.error('Error cargando carrito:', error);
            });
    }

    // Renderizar items del carrito
    function renderizarCarrito(items, total) {
        cartItems.innerHTML = items.map(item => `
            <div class="cart-item" data-product-id="${item.id_producto}">
                <img src="https://via.placeholder.com/80x80?text=Joya" 
                        alt="${item.nombre}" 
                        class="cart-item-image">
                <div class="cart-item-details">
                    <div class="cart-item-name">${item.nombre}</div>
                    <div class="cart-item-sku">SKU: ${item.sku || 'N/A'}</div>
                    <div class="cart-item-price">$${parseFloat(item.precio).toLocaleString('es-MX', { minimumFractionDigits: 2 })}</div>
                    <div class="cart-item-controls">
                        <div class="cart-item-quantity">
                            <button onclick="decrementarCantidad(${item.id_producto})" type="button">-</button>
                            <input type="number" 
                                    value="${item.cantidad}" 
                                    min="1" 
                                    onchange="actualizarCantidad(${item.id_producto}, this.value)"
                                    readonly>
                            <button onclick="incrementarCantidad(${item.id_producto})" type="button">+</button>
                        </div>
                        <button class="cart-item-remove" onclick="eliminarDelCarrito(${item.id_producto})" type="button">
                            <i class="bi bi-trash"></i>
                        </button>
                    </div>
                    <div class="cart-item-total">
                        Subtotal: $${(parseFloat(item.precio) * item.cantidad).toLocaleString('es-MX', { minimumFractionDigits: 2 })}
                    </div>
                </div>
            </div>
        `).join('');

        cartTotal.textContent = '$' + parseFloat(total).toLocaleString('es-MX', { minimumFractionDigits: 2 });
    }

    // Actualizar badge del carrito (hacerla global para que pueda ser llamada desde otros scripts)
    window.actualizarBadgeCarrito = function (totalItems) {
        if (cartBadge) {
            cartBadge.textContent = totalItems || 0;
            if (totalItems > 0) {
                cartBadge.style.display = 'flex';
            } else {
                cartBadge.style.display = 'none';
            }
        }
    };

    // Funciones globales para los botones del carrito
    window.incrementarCantidad = function (idProducto) {
        const item = document.querySelector(`.cart-item[data-product-id="${idProducto}"]`);
        const input = item.querySelector('input[type="number"]');
        const nuevaCantidad = parseInt(input.value) + 1;
        actualizarCantidad(idProducto, nuevaCantidad);
    };

    window.decrementarCantidad = function (idProducto) {
        const item = document.querySelector(`.cart-item[data-product-id="${idProducto}"]`);
        const input = item.querySelector('input[type="number"]');
        const nuevaCantidad = Math.max(1, parseInt(input.value) - 1);
        actualizarCantidad(idProducto, nuevaCantidad);
    };

    window.actualizarCantidad = function (idProducto, cantidad) {
        fetch('/api/carrito/actualizar', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                id_producto: idProducto,
                cantidad: parseInt(cantidad)
            })
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    cargarCarrito();
                } else {
                    alert('Error: ' + (data.error || 'No se pudo actualizar la cantidad'));
                    cargarCarrito(); // Recargar para restaurar valores
                }
            })
            .catch(error => {
                console.error('Error:', error);
                alert('Error al actualizar cantidad');
                cargarCarrito();
            });
    };

    window.eliminarDelCarrito = function (idProducto) {
        if (!confirm('¿Estás seguro de eliminar este producto del carrito?')) {
            return;
        }

        fetch('/api/carrito/eliminar', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                id_producto: idProducto
            })
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    cargarCarrito();
                    actualizarBadgeCarrito(data.total_items);
                } else {
                    alert('Error: ' + (data.error || 'No se pudo eliminar el producto'));
                }
            })
            .catch(error => {
                console.error('Error:', error);
                alert('Error al eliminar producto');
            });
    };

    // Botón Pagar - Flujo completo de checkout
    if (btnPagar) {
        btnPagar.addEventListener('click', function () {
            // Obtener carrito actual
            fetch('/api/carrito/obtener')
                .then(r => r.json())
                .then(carritoData => {
                    if (!carritoData.carrito || carritoData.carrito.length === 0) {
                        alert('El carrito está vacío');
                        return;
                    }

                    // Deshabilitar botón
                    btnPagar.disabled = true;
                    btnPagar.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Procesando...';

                    // Verificar si se solicita factura
                    const checkSolicitarFactura = document.getElementById('checkSolicitarFactura');
                    const solicitarFactura = checkSolicitarFactura ? checkSolicitarFactura.checked : false;
                    
                    // Crear pedido desde el carrito
                    fetch('/api/carrito/checkout', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json'
                        },
                        body: JSON.stringify({
                            solicitar_factura: solicitarFactura
                        })
                    })
                        .then(response => {
                            if (response.status === 401) {
                                // Usuario no autenticado
                                return response.json().then(data => {
                                    if (data.require_login || data.error === 'ERROR_SIN_CLIENTE') {
                                        // Guardar el carrito en sessionStorage para restaurarlo después del login
                                        if (carritoData && carritoData.carrito) {
                                            sessionStorage.setItem('carrito_pendiente', JSON.stringify(carritoData.carrito));
                                        }
                                        // Redirigir automáticamente al login
                                        window.location.href = '/login';
                                        return Promise.resolve({ redirected: true });
                                    }
                                    throw new Error(data.error || 'Debe iniciar sesión');
                                });
                            }
                            if (!response.ok) {
                                // Clonar la respuesta para poder leerla múltiples veces
                                const responseClone = response.clone();
                                // Intentar parsear la respuesta como JSON
                                return response.json().then(err => {
                                    console.log('[DEBUG] Error response:', err);
                                    // Si requiere completar datos, redirigir a la página de completar datos
                                    if (err && err.require_complete_data) {
                                        console.log('[DEBUG] Requiere completar datos, redirigiendo a /cliente/completar-datos');
                                        // Guardar el carrito en sessionStorage para restaurarlo después
                                        if (carritoData && carritoData.carrito) {
                                            sessionStorage.setItem('carrito_pendiente', JSON.stringify(carritoData.carrito));
                                            console.log('[DEBUG] Carrito guardado en sessionStorage:', carritoData.carrito.length, 'items');
                                        }
                                        // Redirigir inmediatamente a la página de completar datos
                                        window.location.href = '/cliente/completar-datos';
                                        // Retornar una promesa resuelta para evitar que se ejecute el catch
                                        return Promise.resolve({ redirected: true });
                                    }
                                    // Si requiere login (ERROR_SIN_CLIENTE), redirigir al login
                                    if (err && (err.require_login || err.error === 'ERROR_SIN_CLIENTE')) {
                                        console.log('[DEBUG] Usuario no autenticado, redirigiendo a /login');
                                        // Guardar el carrito en sessionStorage para restaurarlo después del login
                                        if (carritoData && carritoData.carrito) {
                                            sessionStorage.setItem('carrito_pendiente', JSON.stringify(carritoData.carrito));
                                            console.log('[DEBUG] Carrito guardado en sessionStorage:', carritoData.carrito.length, 'items');
                                        }
                                        // Redirigir automáticamente al login
                                        window.location.href = '/login';
                                        return Promise.resolve({ redirected: true });
                                    }
                                    // Si no requiere completar datos, rechazar la promesa con el error
                                    const errorObj = new Error(err.mensaje || err.error || 'Error al procesar el checkout');
                                    errorObj.errorData = err;
                                    return Promise.reject(errorObj);
                                }).catch(parseError => {
                                    console.error('[DEBUG] Error parseando JSON de error:', parseError);
                                    // Si no se puede parsear el JSON, intentar leer el texto del clon
                                    return responseClone.text().then(text => {
                                        console.log('[DEBUG] Respuesta de error (texto):', text);
                                        // Si el texto contiene ERROR_FALTA_RFC o require_complete_data, redirigir
                                        if (text.includes('ERROR_FALTA_RFC') || text.includes('require_complete_data') || text.includes('ERROR_FALTA_DIRECCION') || text.includes('ERROR_FALTA_TELEFONO')) {
                                            console.log('[DEBUG] Detectado error de datos faltantes en texto, redirigiendo...');
                                            if (carritoData && carritoData.carrito) {
                                                sessionStorage.setItem('carrito_pendiente', JSON.stringify(carritoData.carrito));
                                                console.log('[DEBUG] Carrito guardado en sessionStorage (fallback):', carritoData.carrito.length, 'items');
                                            }
                                            window.location.href = '/cliente/completar-datos';
                                            return Promise.resolve({ redirected: true });
                                        }
                                        // Si el texto contiene ERROR_SIN_CLIENTE o require_login, redirigir al login
                                        if (text.includes('ERROR_SIN_CLIENTE') || text.includes('require_login')) {
                                            console.log('[DEBUG] Detectado error de usuario no autenticado en texto, redirigiendo a /login...');
                                            if (carritoData && carritoData.carrito) {
                                                sessionStorage.setItem('carrito_pendiente', JSON.stringify(carritoData.carrito));
                                                console.log('[DEBUG] Carrito guardado en sessionStorage (fallback):', carritoData.carrito.length, 'items');
                                            }
                                            window.location.href = '/login';
                                            return Promise.resolve({ redirected: true });
                                        }
                                        const errorObj = new Error('Error al procesar el checkout');
                                        errorObj.errorData = { error: text };
                                        return Promise.reject(errorObj);
                                    });
                                });
                            }
                            return response.json();
                        })
                        .then(data => {
                            // Si se redirigió, no hacer nada más
                            if (data && data.redirected) {
                                return;
                            }
                            if (data && data.require_complete_data) {
                                // Guardar el carrito en sessionStorage para restaurarlo después
                                if (carritoData && carritoData.carrito) {
                                    sessionStorage.setItem('carrito_pendiente', JSON.stringify(carritoData.carrito));
                                }
                                // Redirigir a la página de completar datos
                                window.location.href = '/cliente/completar-datos';
                                return;
                            }
                            if (data.success) {
                                // Siempre mostrar modal de pago, con o sin factura
                                // Si no hay factura, se creará automáticamente cuando se registre el pago
                                // Pasar también el descuento de clasificación si existe
                                abrirModalPagoCheckout(data.id_pedido, data.id_factura, data.total, data.descuento_clasificacion, data.total_sin_descuento_clasificacion);
                            } else {
                                // Mostrar mensaje amigable (el backend ya retorna mensajes amigables)
                                const mensaje = data.mensaje || data.error || 'No se pudo procesar el checkout';
                                alert(mensaje);
                                btnPagar.disabled = false;
                                btnPagar.innerHTML = '<i class="bi bi-credit-card"></i> Pagar';
                            }
                        })
                        .catch(error => {
                            console.error('Error en checkout:', error);
                            // Verificar si ya se redirigió (no mostrar alert si se redirigió)
                            if (window.location.pathname === '/cliente/completar-datos') {
                                console.log('[DEBUG] Ya se redirigió a completar datos, no mostrar error');
                                return;
                            }
                            // Si el error tiene require_complete_data o errorData con require_complete_data, ya se manejó
                            if (error.require_complete_data || (error.errorData && error.errorData.require_complete_data)) {
                                console.log('[DEBUG] Error ya manejado con require_complete_data');
                                return;
                            }
                            // Si el error tiene un mensaje de redirección, no mostrar alert
                            if (error.message && (error.message.includes('redirected') || error.message.includes('Redirigiendo'))) {
                                console.log('[DEBUG] Error de redirección, no mostrar alert');
                                return;
                            }
                            // Si el error contiene información de datos faltantes, redirigir
                            const errorStr = JSON.stringify(error);
                            if (errorStr.includes('ERROR_FALTA_RFC') || errorStr.includes('ERROR_FALTA_DIRECCION') || errorStr.includes('ERROR_FALTA_TELEFONO') || errorStr.includes('require_complete_data')) {
                                console.log('[DEBUG] Detectado error de datos faltantes en catch, redirigiendo...');
                                if (carritoData && carritoData.carrito) {
                                    sessionStorage.setItem('carrito_pendiente', JSON.stringify(carritoData.carrito));
                                }
                                window.location.href = '/cliente/completar-datos';
                                return;
                            }
                            // Si el error contiene ERROR_SIN_CLIENTE, redirigir al login
                            if (errorStr.includes('ERROR_SIN_CLIENTE') || errorStr.includes('require_login')) {
                                console.log('[DEBUG] Detectado error de usuario no autenticado en catch, redirigiendo a /login...');
                                if (carritoData && carritoData.carrito) {
                                    sessionStorage.setItem('carrito_pendiente', JSON.stringify(carritoData.carrito));
                                }
                                window.location.href = '/login';
                                return;
                            }
                            // Mostrar el error al usuario solo si no se redirigió
                            const errorMsg = (error.errorData && error.errorData.mensaje) || 
                                          (error.errorData && error.errorData.error) || 
                                          error.error || 
                                          error.message || 
                                          'Lo sentimos, hubo un problema al procesar tu pedido. Por favor, intenta nuevamente.';
                            // Si el mensaje ya empieza con "Error:", no agregarlo de nuevo
                            const mensajeFinal = errorMsg.startsWith('Error:') || errorMsg.startsWith('Lo sentimos') ? errorMsg : ('Error: ' + errorMsg);
                            alert(mensajeFinal);
                            btnPagar.disabled = false;
                            btnPagar.innerHTML = '<i class="bi bi-credit-card"></i> Pagar';
                        });
                })
                .catch(error => {
                    console.error('Error obteniendo carrito:', error);
                    alert('Error al obtener el carrito');
                    btnPagar.disabled = false;
                    btnPagar.innerHTML = '<i class="bi bi-credit-card"></i> Pagar';
                });
        });
    }

    // Función para abrir modal de pago desde checkout
    function abrirModalPagoCheckout(idPedido, idFactura, total, descuentoClasificacion = 0, totalSinDescuentoClasificacion = null) {
        // Obtener métodos de pago
        fetch('/api/ventas/pagos/metodos')
            .then(r => r.json())
            .then(metodos => {
                const selectMetodo = document.getElementById('pagoCheckoutMetodo');
                if (selectMetodo) {
                    selectMetodo.innerHTML = '<option value="">Seleccione un método...</option>';
                    metodos.forEach(metodo => {
                        selectMetodo.innerHTML += `<option value="${metodo.id_metodo_pago}">${metodo.nombre_metodo_pago}</option>`;
                    });
                }

                document.getElementById('pagoCheckoutIdPedido').value = idPedido;
                // Si no hay factura, dejar el campo vacío (se creará al pagar)
                document.getElementById('pagoCheckoutIdFactura').value = idFactura || '';
                
                // Mostrar descuento de clasificación si existe
                const totalElement = document.getElementById('pagoCheckoutTotal');
                const descuentoInfo = document.getElementById('pagoCheckoutDescuentoClasificacion');
                
                if (descuentoClasificacion && descuentoClasificacion > 0 && totalSinDescuentoClasificacion) {
                    // Mostrar total sin descuento tachado y el descuento aplicado
                    if (descuentoInfo) {
                        descuentoInfo.innerHTML = `
                            <div class="mb-2">
                                <span class="text-muted text-decoration-line-through" style="font-size: 0.9rem;">
                                    Subtotal: $${parseFloat(totalSinDescuentoClasificacion).toLocaleString('es-MX', { minimumFractionDigits: 2 })}
                                </span>
                                <span class="badge bg-success ms-2">Descuento Cliente: -${descuentoClasificacion}%</span>
                            </div>
                        `;
                        descuentoInfo.style.display = 'block';
                    }
                    totalElement.textContent = '$' + parseFloat(total).toLocaleString('es-MX', { minimumFractionDigits: 2 });
                } else {
                    // No hay descuento de clasificación
                    if (descuentoInfo) {
                        descuentoInfo.style.display = 'none';
                        descuentoInfo.innerHTML = '';
                    }
                    totalElement.textContent = '$' + parseFloat(total).toLocaleString('es-MX', { minimumFractionDigits: 2 });
                }
                
                document.getElementById('pagoCheckoutImporte').value = total;
                document.getElementById('pagoCheckoutImporte').max = total;

                const modal = new bootstrap.Modal(document.getElementById('modalPagoCheckout'));
                modal.show();

                // Rehabilitar botón pagar
                btnPagar.disabled = false;
                btnPagar.innerHTML = '<i class="bi bi-credit-card"></i> Pagar';
            })
            .catch(err => {
                console.error('Error obteniendo métodos de pago:', err);
                alert('Error al cargar métodos de pago');
                btnPagar.disabled = false;
                btnPagar.innerHTML = '<i class="bi bi-credit-card"></i> Pagar';
            });
    }

    // Registrar pago desde checkout (función global)
    window.registrarPagoCheckout = function () {
        const form = document.getElementById('formPagoCheckout');
        if (!form.checkValidity()) {
            form.reportValidity();
            return;
        }

        const data = {
            id_pedido: parseInt(document.getElementById('pagoCheckoutIdPedido').value),
            importe: parseFloat(document.getElementById('pagoCheckoutImporte').value),
            id_metodo_pago: parseInt(document.getElementById('pagoCheckoutMetodo').value)
        };

        const btn = document.getElementById('btnRegistrarPagoCheckout');
        btn.disabled = true;
        btn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Procesando...';

        fetch(`/api/ventas/pedidos/${data.id_pedido}/pagar`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                importe: data.importe,
                id_metodo_pago: data.id_metodo_pago
            })
        })
            .then(response => {
                // Verificar si la respuesta es exitosa
                if (!response.ok) {
                    // Intentar parsear el error
                    return response.json().then(err => {
                        throw new Error(err.mensaje || err.error || 'Error al registrar el pago');
                    });
                }
                return response.json();
            })
            .then(data => {
                if (data.success) {
                    alert(data.mensaje || '¡Pago registrado exitosamente!');

                    // Cerrar modal
                    const modal = bootstrap.Modal.getInstance(document.getElementById('modalPagoCheckout'));
                    if (modal) modal.hide();

                    // Vaciar carrito
                    fetch('/api/carrito/vaciar', { method: 'POST' })
                        .then(() => {
                            cargarCarrito();
                            window.actualizarBadgeCarrito(0);
                            cerrarCarrito();

                            // Redirigir a página de éxito o catálogo
                            alert('¡Gracias por su compra!');
                            window.location.href = URL_CATALOGO;
                        });
                } else {
                    alert('Error: ' + (data.mensaje || data.error || 'No se pudo registrar el pago'));
                    btn.disabled = false;
                    btn.innerHTML = '<i class="bi bi-credit-card"></i> Registrar Pago';
                }
            })
            .catch(error => {
                console.error('Error:', error);
                alert('Error: ' + (error.message || 'Error al registrar el pago. Por favor, intente nuevamente.'));
                btn.disabled = false;
                btn.innerHTML = '<i class="bi bi-credit-card"></i> Registrar Pago';
            });
    };

    // Cargar carrito al iniciar
    cargarCarrito();
})();
