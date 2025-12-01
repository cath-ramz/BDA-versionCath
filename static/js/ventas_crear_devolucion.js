(function () {
    document.addEventListener('DOMContentLoaded', function () {
        const selectPedido = document.getElementById('id_pedido');
        const productosContainer = document.getElementById('productosContainer');
        const productosList = document.getElementById('productosList');
        const form = document.getElementById('formDevolucion');
        const btnCrear = form ? form.querySelector('button[type="submit"]') : null;

        // Obtener tipos y motivos desde el template (si están disponibles)
        let tiposDevolucion = [];
        let motivosDevolucion = [];

        // Intentar obtener desde variables globales si están definidas
        if (typeof TIPOS_DEVOLUCION !== 'undefined' && Array.isArray(TIPOS_DEVOLUCION)) {
            tiposDevolucion = TIPOS_DEVOLUCION;
        }
        if (typeof MOTIVOS_DEVOLUCION !== 'undefined' && Array.isArray(MOTIVOS_DEVOLUCION)) {
            motivosDevolucion = MOTIVOS_DEVOLUCION;
        }

        // Generar opciones de tipos
        function generarOpcionesTipos() {
            let html = '<option value="">Seleccione...</option>';
            if (tiposDevolucion && tiposDevolucion.length > 0) {
                tiposDevolucion.forEach(tipo => {
                    const id = tipo.id || tipo.id_tipo_devoluciones || '';
                    const nombre = tipo.nombre || tipo.tipo_devolucion || '';
                    if (id && nombre) {
                        html += `<option value="${id}">${nombre}</option>`;
                    }
                });
            }
            return html;
        }

        // Generar opciones de motivos
        function generarOpcionesMotivos() {
            let html = '<option value="">Seleccione...</option>';
            if (motivosDevolucion && motivosDevolucion.length > 0) {
                motivosDevolucion.forEach(motivo => {
                    const valor = typeof motivo === 'string' ? motivo : (motivo.motivo_devolucion || motivo);
                    if (valor) {
                        html += `<option value="${valor}">${valor}</option>`;
                    }
                });
            }
            return html;
        }

        // Cargar productos cuando se selecciona un pedido
        if (selectPedido) {
            selectPedido.addEventListener('change', function () {
                const idPedido = this.value;
                if (idPedido) {
                    cargarProductos(idPedido);
                } else {
                    productosContainer.style.display = 'none';
                    productosList.innerHTML = '';
                }
            });
        }

        // Si hay un id_pedido en la URL, seleccionarlo automáticamente
        const urlParams = new URLSearchParams(window.location.search);
        const idPedidoUrl = urlParams.get('id_pedido');
        if (idPedidoUrl && selectPedido) {
            selectPedido.value = idPedidoUrl;
            selectPedido.dispatchEvent(new Event('change'));
        }

        function cargarProductos(idPedido) {
            productosList.innerHTML = '<p class="text-muted">Cargando productos...</p>';
            productosContainer.style.display = 'block';

            fetch(`/api/ventas/devoluciones/pedido/${idPedido}/productos`)
                .then(response => {
                    if (!response.ok) {
                        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                    }
                    return response.json();
                })
                .then(productos => {
                    if (productos && productos.length > 0) {
                        productosList.innerHTML = '';
                        productos.forEach(producto => {
                            const idProducto = producto.id_producto || producto.get('id_producto');
                            const idPedidoDetalle = producto.id_pedido_detalle || producto.get('id_pedido_detalle');
                            const nombreProducto = producto.nombre_producto || producto.get('nombre_producto') || 'N/A';
                            const sku = producto.sku || producto.get('sku') || 'N/A';
                            const cantidad = producto.cantidad_producto || producto.get('cantidad_producto') || 0;
                            const precio = producto.precio_unitario || producto.get('precio_unitario') || 0;

                            const productItem = document.createElement('div');
                            productItem.className = 'product-item mb-3 p-3 border rounded';
                            productItem.innerHTML = `
                                <div class="product-item-header d-flex align-items-center mb-2">
                                    <input type="checkbox" class="product-checkbox form-check-input me-2" 
                                           data-id-producto="${idProducto}" 
                                           data-id-pedido-detalle="${idPedidoDetalle}"
                                           data-cantidad-maxima="${cantidad}">
                                    <strong>${nombreProducto}</strong>
                                    <span class="badge bg-secondary ms-2">SKU: ${sku}</span>
                                    <span class="ms-auto">Cantidad: ${cantidad} | Precio: $${parseFloat(precio).toFixed(2)}</span>
                                </div>
                                <div class="product-details" style="display: none; margin-top: 12px;">
                                    <div class="row g-3">
                                        <div class="col-md-3">
                                            <label class="form-label small">Cantidad a devolver <span class="text-danger">*</span></label>
                                            <input type="number" class="form-control cantidad-input" 
                                                   min="1" max="${cantidad}" value="1"
                                                   data-id-producto="${idProducto}">
                                        </div>
                                        <div class="col-md-4">
                                            <label class="form-label small">Tipo de devolución <span class="text-danger">*</span></label>
                                            <select class="form-select tipo-devolucion-select" 
                                                    data-id-producto="${idProducto}">
                                                ${generarOpcionesTipos()}
                                            </select>
                                        </div>
                                        <div class="col-md-5">
                                            <label class="form-label small">Motivo <span class="text-danger">*</span></label>
                                            <select class="form-select motivo-select" 
                                                    data-id-producto="${idProducto}">
                                                ${generarOpcionesMotivos()}
                                            </select>
                                        </div>
                                    </div>
                                </div>
                            `;
                            productosList.appendChild(productItem);

                            // Mostrar/ocultar detalles cuando se marca el checkbox
                            const checkbox = productItem.querySelector('.product-checkbox');
                            const details = productItem.querySelector('.product-details');
                            checkbox.addEventListener('change', function () {
                                details.style.display = this.checked ? 'block' : 'none';
                                if (!this.checked) {
                                    // Limpiar campos cuando se desmarca
                                    productItem.querySelector('.cantidad-input').value = '1';
                                    productItem.querySelector('.tipo-devolucion-select').value = '';
                                    productItem.querySelector('.motivo-select').value = '';
                                }
                            });
                        });
                    } else {
                        productosContainer.style.display = 'none';
                        productosList.innerHTML = '<p class="text-muted">No hay productos disponibles para este pedido.</p>';
                    }
                })
                .catch(error => {
                    console.error('Error cargando productos:', error);
                    productosList.innerHTML = '<p class="text-danger">Error al cargar productos del pedido</p>';
                });
        }

        // Manejar envío del formulario
        if (form) {
            form.addEventListener('submit', function (e) {
                e.preventDefault();

                const idPedido = selectPedido ? selectPedido.value : '';
                if (!idPedido) {
                    alert('Por favor seleccione un pedido');
                    return;
                }

                // Validar que al menos un producto esté seleccionado
                const productosSeleccionados = document.querySelectorAll('.product-checkbox:checked');
                if (productosSeleccionados.length === 0) {
                    alert('Por favor seleccione al menos un producto para devolver');
                    return;
                }

                // Validar campos de cada producto seleccionado
                const items = [];
                let hayErrores = false;

                productosSeleccionados.forEach(checkbox => {
                    const idProducto = checkbox.getAttribute('data-id-producto');
                    const cantidadInput = document.querySelector(`.cantidad-input[data-id-producto="${idProducto}"]`);
                    const tipoSelect = document.querySelector(`.tipo-devolucion-select[data-id-producto="${idProducto}"]`);
                    const motivoSelect = document.querySelector(`.motivo-select[data-id-producto="${idProducto}"]`);

                    const cantidad = parseInt(cantidadInput ? cantidadInput.value : 0) || 0;
                    const idTipoDevolucion = tipoSelect ? tipoSelect.value : '';
                    const motivo = motivoSelect ? motivoSelect.value : '';

                    if (cantidad <= 0) {
                        alert(`Por favor ingrese una cantidad válida para el producto seleccionado`);
                        hayErrores = true;
                        return;
                    }

                    if (!idTipoDevolucion) {
                        alert(`Por favor seleccione un tipo de devolución para el producto seleccionado`);
                        hayErrores = true;
                        return;
                    }

                    if (!motivo) {
                        alert(`Por favor seleccione un motivo para el producto seleccionado`);
                        hayErrores = true;
                        return;
                    }

                    items.push({
                        id_producto: parseInt(idProducto),
                        cantidad: cantidad,
                        id_tipo_devolucion: parseInt(idTipoDevolucion),
                        motivo: motivo
                    });
                });

                if (hayErrores) {
                    return;
                }

                // Deshabilitar botón
                if (btnCrear) {
                    btnCrear.disabled = true;
                    btnCrear.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Procesando...';
                }

                // Enviar a la API
                console.log('Enviando datos:', { id_pedido: parseInt(idPedido), items: items });
                fetch('/api/ventas/devoluciones/crear', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        id_pedido: parseInt(idPedido),
                        items: items
                    })
                })
                    .then(response => {
                        if (!response.ok) {
                            return response.json().then(data => {
                                throw new Error(data.error || data.mensaje || `HTTP ${response.status}`);
                            });
                        }
                        return response.json();
                    })
                    .then(data => {
                        if (data.success || data.id_devolucion) {
                            alert('Devolución creada exitosamente');
                            window.location.href = '/ventas/devoluciones';
                        } else {
                            const errorMsg = data.mensaje || data.error || 'Error al crear la devolución';
                            alert('Error: ' + errorMsg);
                            if (btnCrear) {
                                btnCrear.disabled = false;
                                btnCrear.innerHTML = '<i class="bi bi-check-circle"></i> Crear Devolución';
                            }
                        }
                    })
                    .catch(error => {
                        console.error('Error:', error);
                        alert('Error al crear la devolución: ' + error.message);
                        if (btnCrear) {
                            btnCrear.disabled = false;
                            btnCrear.innerHTML = '<i class="bi bi-check-circle"></i> Crear Devolución';
                        }
                    });
            });
        }
    });
})();

