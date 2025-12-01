(function () {
    document.addEventListener('DOMContentLoaded', function () {
        const selectPedido = document.getElementById('id_pedido');
        const productosContainer = document.getElementById('productosContainer');
        const productosList = document.getElementById('productosList');
        const form = document.getElementById('formCrearDevolucion');
        const btnCrear = document.getElementById('btnCrearDevolucion');

        // Generar opciones de tipos
        function generarOpcionesTipos() {
            let html = '<option value="">Seleccione...</option>';
            if (typeof TIPOS_DEVOLUCION !== 'undefined') {
                TIPOS_DEVOLUCION.forEach(tipo => {
                    html += `<option value="${tipo.id}">${tipo.nombre}</option>`;
                });
            }
            return html;
        }

        // Generar opciones de motivos
        function generarOpcionesMotivos() {
            let html = '<option value="">Seleccione...</option>';
            if (typeof MOTIVOS_DEVOLUCION !== 'undefined') {
                MOTIVOS_DEVOLUCION.forEach(motivo => {
                    html += `<option value="${motivo}">${motivo}</option>`;
                });
            }
            return html;
        }

        // Cargar productos cuando se selecciona un pedido
        selectPedido.addEventListener('change', function () {
            const idPedido = this.value;
            if (idPedido) {
                cargarProductos(idPedido);
            } else {
                productosContainer.style.display = 'none';
                productosList.innerHTML = '';
            }
        });

        function cargarProductos(idPedido) {
            fetch(`/api/ventas/devoluciones/pedido/${idPedido}/productos`)
                .then(response => response.json())
                .then(productos => {
                    if (productos && productos.length > 0) {
                        productosList.innerHTML = '';
                        productos.forEach(producto => {
                            const productItem = document.createElement('div');
                            productItem.className = 'product-item';
                            productItem.innerHTML = `
                                <div class="product-item-header">
                                    <input type="checkbox" class="product-checkbox form-check-input" 
                                           data-id-producto="${producto.id_producto}" 
                                           data-id-pedido-detalle="${producto.id_pedido_detalle}"
                                           data-cantidad-maxima="${producto.cantidad_producto}">
                                    <strong>${producto.nombre_producto}</strong>
                                    <span class="badge bg-secondary ms-2">SKU: ${producto.sku}</span>
                                    <span class="ms-auto">Cantidad en pedido: ${producto.cantidad_producto}</span>
                                </div>
                                <div class="product-details" style="display: none; margin-top: 12px;">
                                    <div class="row g-3">
                                        <div class="col-md-3">
                                            <label class="form-label small">Cantidad a devolver <span class="text-danger">*</span></label>
                                            <input type="number" class="form-control cantidad-input" 
                                                   min="1" max="${producto.cantidad_producto}" value="1"
                                                   data-id-producto="${producto.id_producto}">
                                        </div>
                                        <div class="col-md-4">
                                            <label class="form-label small">Tipo de devolución <span class="text-danger">*</span></label>
                                            <select class="form-select tipo-devolucion-select" 
                                                    data-id-producto="${producto.id_producto}">
                                                ${generarOpcionesTipos()}
                                            </select>
                                        </div>
                                        <div class="col-md-5">
                                            <label class="form-label small">Motivo <span class="text-danger">*</span></label>
                                            <select class="form-select motivo-select" 
                                                    data-id-producto="${producto.id_producto}">
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
                        productosContainer.style.display = 'block';
                    } else {
                        productosContainer.style.display = 'none';
                        productosList.innerHTML = '<p class="text-muted">No hay productos disponibles para este pedido.</p>';
                    }
                })
                .catch(error => {
                    console.error('Error cargando productos:', error);
                    alert('Error al cargar productos del pedido');
                });
        }

        // Enviar formulario al hacer click en el botón
        btnCrear.addEventListener('click', function () {
            console.log('Botón crear devolución clickeado');

            const idPedido = selectPedido.value;
            console.log('ID Pedido:', idPedido);
            if (!idPedido) {
                alert('Por favor seleccione un pedido');
                return;
            }

            // Validar que al menos un producto esté seleccionado
            const productosSeleccionados = document.querySelectorAll('.product-checkbox:checked');
            console.log('Productos seleccionados:', productosSeleccionados.length);
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

                const cantidad = parseInt(cantidadInput.value) || 0;
                const idTipoDevolucion = tipoSelect.value;
                const motivo = motivoSelect.value;

                console.log('Validando producto:', { idProducto, cantidad, idTipoDevolucion, motivo });

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
            btnCrear.disabled = true;
            btnCrear.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Procesando...';

            // Enviar a la API (usa el mismo endpoint que ventas)
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
                .then(response => response.json())
                .then(data => {
                    if (data.success || data.id_devolucion) {
                        alert('Devolución creada exitosamente');
                        window.location.href = '/admin/devoluciones';
                    } else {
                        const errorMsg = data.mensaje || data.error || 'Error al crear la devolución';
                        alert('Error: ' + errorMsg);
                        btnCrear.disabled = false;
                        btnCrear.innerHTML = '<i class="bi bi-check-circle"></i> Crear Devolución';
                    }
                })
                .catch(error => {
                    console.error('Error:', error);
                    alert('Error al crear la devolución. Por favor, intente de nuevo.');
                    btnCrear.disabled = false;
                    btnCrear.innerHTML = '<i class="bi bi-check-circle"></i> Crear Devolución';
                });
        });
    });
})();
