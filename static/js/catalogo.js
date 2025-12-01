// Búsqueda de productos
document.getElementById('searchInput')?.addEventListener('input', function (e) {
    const searchTerm = e.target.value.toLowerCase();
    const cards = document.querySelectorAll('.product-card');

    cards.forEach(card => {
        const productName = card.querySelector('.product-name').textContent.toLowerCase();
        const cardContainer = card.closest('.col-md-4');

        if (productName.includes(searchTerm)) {
            cardContainer.style.display = '';
        } else {
            cardContainer.style.display = 'none';
        }
    });
});

// Efecto visual en botones de categoría al hacer clic
document.querySelectorAll('.btn-categoria').forEach(btn => {
    btn.addEventListener('click', function () {
        // El estado activo se maneja desde el servidor con la clase 'active'
        // Solo agregamos un pequeño feedback visual
        this.style.transform = 'scale(0.95)';
        setTimeout(() => {
            this.style.transform = '';
        }, 150);
    });
});

// Función para ver detalles del producto
function verDetalles(idProducto) {
    const modal = new bootstrap.Modal(document.getElementById('modalVerDetalles'));
    const modalBody = document.getElementById('modalDetallesBody');
    const btnAgregar = document.getElementById('btnAgregarDesdeModal');
    
    // Mostrar loading
    modalBody.innerHTML = `
        <div class="text-center py-4">
            <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">Cargando...</span>
            </div>
            <p class="mt-2 text-muted">Cargando información del producto...</p>
        </div>
    `;
    
    // Ocultar botón agregar mientras carga
    btnAgregar.style.display = 'none';
    
    // Abrir modal
    modal.show();
    
    // Cargar datos del producto
    fetch(`/api/productos/ver/${idProducto}`)
        .then(response => {
            if (!response.ok) {
                throw new Error('Error al cargar los detalles del producto');
            }
            return response.json();
        })
        .then(data => {
            const precioOriginal = data.precio_unitario;
            const descuento = data.descuento_producto || 0;
            // Aplicar descuento: precio - precio*descuento
            const precioFinal = precioOriginal - (precioOriginal * descuento / 100);
            
            // Construir URL de imagen
            let imagenUrl = '/static/images/defaults/joyeria-default.png';
            if (data.imagen_url) {
                if (data.imagen_url.startsWith('/static/')) {
                    imagenUrl = data.imagen_url;
                } else if (data.imagen_url.startsWith('static/')) {
                    imagenUrl = '/' + data.imagen_url;
                } else {
                    const cleanUrl = data.imagen_url.startsWith('/') ? data.imagen_url.substring(1) : data.imagen_url;
                    imagenUrl = '/static/' + cleanUrl;
                }
            }
            const imagenDefault = '/static/images/defaults/joyeria-default.png';
            
            const stockTotal = data.stock_total || 0;
            const disponible = stockTotal > 0;
            
            // Construir HTML del modal
            modalBody.innerHTML = `
                <div class="row">
                    <div class="col-md-5 mb-4">
                        <img src="${imagenUrl}" 
                             alt="${data.nombre_producto}" 
                             class="img-fluid rounded"
                             style="width: 100%; height: 400px; object-fit: cover;"
                             onerror="this.src='${imagenDefault}'">
                    </div>
                    <div class="col-md-7 mb-4">
                        <h3 class="mb-3" style="color: #1e293b;">${data.nombre_producto}</h3>
                        <div class="mb-4">
                            ${descuento > 0 ? `
                                <div class="mb-2">
                                    <span class="text-muted text-decoration-line-through" style="font-size: 1.1rem;">
                                        $${precioOriginal.toLocaleString('es-MX', {minimumFractionDigits: 2, maximumFractionDigits: 2})}
                                    </span>
                                    <span class="badge bg-danger ms-2">-${descuento}%</span>
                                </div>
                                <div class="mb-2">
                                    <span style="font-size: 2rem; font-weight: 700; color: #ff9500;">
                                        $${precioFinal.toLocaleString('es-MX', {minimumFractionDigits: 2, maximumFractionDigits: 2})}
                                    </span>
                                </div>
                            ` : `
                                <div class="mb-2">
                                    <span style="font-size: 2rem; font-weight: 700; color: #ff9500;">
                                        $${precioFinal.toLocaleString('es-MX', {minimumFractionDigits: 2, maximumFractionDigits: 2})}
                                    </span>
                                </div>
                            `}
                        </div>
                        <div class="mb-4">
                            ${disponible 
                                ? `<span class="badge bg-success" style="font-size: 0.9rem; padding: 8px 12px;">
                                    <i class="bi bi-check-circle"></i> Disponible
                                </span>`
                                : `<span class="badge bg-danger" style="font-size: 0.9rem; padding: 8px 12px;">
                                    <i class="bi bi-x-circle"></i> Agotado
                                </span>`}
                        </div>
                        <div class="border-top pt-3">
                            <h6 class="text-primary border-bottom pb-2 mb-3">
                                <i class="bi bi-info-circle"></i> Información del Producto
                            </h6>
                            <table class="table table-sm">
                                <tr>
                                    <td class="fw-bold" style="width: 40%;">Categoría:</td>
                                    <td>${data.nombre_categoria || 'N/A'}</td>
                                </tr>
                                <tr>
                                    <td class="fw-bold">Material:</td>
                                    <td>${data.material || 'N/A'}</td>
                                </tr>
                                <tr>
                                    <td class="fw-bold">Género:</td>
                                    <td>${data.genero_producto || 'N/A'}</td>
                                </tr>
                                ${data.talla ? `<tr><td class="fw-bold">Talla:</td><td>${data.talla}</td></tr>` : ''}
                                ${data.kilataje ? `<tr><td class="fw-bold">Kilataje:</td><td>${data.kilataje}</td></tr>` : ''}
                                ${data.ley ? `<tr><td class="fw-bold">Ley:</td><td>${data.ley}</td></tr>` : ''}
                                <tr>
                                    <td class="fw-bold">SKU:</td>
                                    <td><code class="text-muted">${data.sku || 'N/A'}</code></td>
                                </tr>
                            </table>
                        </div>
                    </div>
                </div>
            `;
            
            // Configurar botón de agregar al carrito
            if (disponible) {
                btnAgregar.style.display = 'inline-block';
                btnAgregar.onclick = () => {
                    agregarAlCarrito(idProducto, btnAgregar);
                    // Ocultar modal después de un breve delay para que el usuario vea el feedback
                    setTimeout(() => {
                        modal.hide();
                    }, 500);
                };
            } else {
                btnAgregar.style.display = 'none';
            }
        })
        .catch(error => {
            console.error('Error:', error);
            modalBody.innerHTML = `
                <div class="alert alert-danger" role="alert">
                    <i class="bi bi-exclamation-triangle"></i> 
                    <strong>Error:</strong> ${error.message || 'No se pudo cargar la información del producto'}
                </div>
            `;
        });
}

// Función para agregar al carrito
function agregarAlCarrito(idProducto, btnElement = null) {
    // Si no se proporciona el botón, intentar encontrarlo desde el evento o por ID
    let btn = btnElement;
    if (!btn && typeof event !== 'undefined' && event.target) {
        btn = event.target.closest('.btn-agregar-carrito');
    }
    if (!btn) {
        // Intentar encontrar el botón del modal
        btn = document.getElementById('btnAgregarDesdeModal');
    }
    
    const originalHTML = btn ? btn.innerHTML : '';

    // Deshabilitar botón temporalmente si existe
    if (btn) {
        btn.disabled = true;
        btn.innerHTML = '<i class="bi bi-hourglass-split"></i> Agregando...';
    }

    fetch('/api/carrito/agregar', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            id_producto: idProducto,
            cantidad: 1
        })
    })
        .then(response => {
            if (!response.ok) {
                return response.json().then(err => Promise.reject(err));
            }
            return response.json();
        })
        .then(data => {
            if (data.success) {
                // Feedback visual solo si hay botón
                if (btn) {
                    btn.innerHTML = '<i class="bi bi-check"></i> Agregado';
                    btn.style.background = '#22c55e';
                    btn.style.borderColor = '#22c55e';
                    btn.style.color = 'white';
                } else {
                    // Mostrar mensaje de éxito si no hay botón
                    alert('¡Producto agregado al carrito exitosamente!');
                }

                // Actualizar badge del carrito
                if (typeof window.actualizarBadgeCarrito === 'function') {
                    window.actualizarBadgeCarrito(data.total_items || 0);
                } else {
                    // Si la función no está disponible, actualizar manualmente
                    const cartBadge = document.getElementById('cartBadge');
                    if (cartBadge) {
                        const totalItems = data.total_items || 0;
                        cartBadge.textContent = totalItems;
                        if (totalItems > 0) {
                            cartBadge.style.display = 'flex';
                        } else {
                            cartBadge.style.display = 'none';
                        }
                    }
                }

                if (btn) {
                    setTimeout(() => {
                        btn.innerHTML = originalHTML;
                        btn.style.background = '';
                        btn.style.borderColor = '';
                        btn.style.color = '';
                        btn.disabled = false;
                    }, 2000);
                }
            } else {
                alert('Error: ' + (data.error || 'No se pudo agregar el producto'));
                if (btn) {
                    btn.innerHTML = originalHTML;
                    btn.disabled = false;
                }
            }
        })
        .catch(error => {
            console.error('Error:', error);
            const errorMsg = error.error || error.message || 'Error al agregar producto al carrito';
            alert('Error: ' + errorMsg);
            if (btn) {
                btn.innerHTML = originalHTML;
                btn.disabled = false;
            }
        });
}
