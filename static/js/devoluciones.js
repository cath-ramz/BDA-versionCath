function verDetallesDevolucion(idDevolucion) {
    // Mostrar modal y cargar datos
    const modal = new bootstrap.Modal(document.getElementById('modalVerDevolucion'));
    const modalBody = document.getElementById('modalDevolucionBody');

    // Mostrar loading
    modalBody.innerHTML = `
        <div class="text-center py-4">
            <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">Cargando...</span>
            </div>
            <p class="mt-2 text-muted">Cargando información de la devolución...</p>
        </div>
    `;

    // Abrir modal
    modal.show();

    // Cargar datos de la devolución
    fetch(`/api/admin/devoluciones/ver/${idDevolucion}`)
        .then(response => {
            if (!response.ok) {
                throw new Error('Error al cargar los detalles de la devolución');
            }
            return response.json();
        })
        .then(data => {
            // Formatear fecha
            const fechaDevolucion = data.fecha_devolucion ? new Date(data.fecha_devolucion).toLocaleDateString('es-MX') : 'N/A';
            const fechaPedido = data.fecha_pedido ? new Date(data.fecha_pedido).toLocaleDateString('es-MX') : 'N/A';

            // Estado badge
            let estadoBadge = '';
            if (data.estado_devolucion === 'Completado') {
                estadoBadge = '<span class="badge bg-success">' + data.estado_devolucion + '</span>';
            } else if (data.estado_devolucion === 'Autorizado') {
                estadoBadge = '<span class="badge bg-info">' + data.estado_devolucion + '</span>';
            } else if (data.estado_devolucion === 'Rechazado') {
                estadoBadge = '<span class="badge bg-danger">' + data.estado_devolucion + '</span>';
            } else if (data.estado_devolucion === 'Pendiente') {
                estadoBadge = '<span class="badge bg-warning">' + data.estado_devolucion + '</span>';
            } else {
                estadoBadge = '<span class="badge bg-secondary">' + (data.estado_devolucion || 'Pendiente') + '</span>';
            }

            // Tabla de productos devueltos
            let productosHtml = '';
            let totalDevolucion = 0;
            if (data.productos && data.productos.length > 0) {
                productosHtml = data.productos.map(item => {
                    totalDevolucion += item.subtotal_devolucion;
                    const reembolsoHtml = item.reembolso ? `
                        <tr>
                            <td colspan="6" class="bg-light">
                                <strong>Reembolso:</strong> 
                                $${item.reembolso.monto_reembolso.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} 
                                - ${item.reembolso.metodo_pago || 'N/A'}
                                ${item.reembolso.fecha_reembolso ? ' - ' + new Date(item.reembolso.fecha_reembolso).toLocaleDateString('es-MX') : ''}
                            </td>
                        </tr>
                    ` : '';
                    return `
                        <tr>
                            <td>${item.nombre_producto || 'N/A'}</td>
                            <td><code class="text-danger">${item.sku || 'N/A'}</code></td>
                            <td>${item.cantidad_devolucion}</td>
                            <td>$${item.precio_unitario.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
                            <td>$${item.subtotal_devolucion.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
                            <td>
                                <span class="badge bg-info">${item.tipo_devolucion || 'N/A'}</span><br>
                                <small class="text-muted">${item.motivo_devolucion || 'Sin motivo'}</small>
                            </td>
                        </tr>
                        ${reembolsoHtml}
                    `;
                }).join('');
            } else {
                productosHtml = '<tr><td colspan="6" class="text-center text-muted">No hay productos devueltos</td></tr>';
            }

            // Construir HTML del modal
            modalBody.innerHTML = `
                <div class="row">
                    <!-- Información Básica -->
                    <div class="col-md-6 mb-4">
                        <h6 class="text-primary border-bottom pb-2 mb-3">
                            <i class="bi bi-info-circle"></i> Información de la Devolución
                        </h6>
                        <table class="table table-sm">
                            <tr>
                                <td class="fw-bold" style="width: 40%;">ID Devolución:</td>
                                <td>#${data.id_devolucion}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">ID Pedido:</td>
                                <td>#${data.id_pedido}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Fecha Devolución:</td>
                                <td>${fechaDevolucion}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Fecha Pedido:</td>
                                <td>${fechaPedido}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Estado:</td>
                                <td>${estadoBadge}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Tipo:</td>
                                <td>${data.tipo_devolucion || 'N/A'}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Cantidad Productos:</td>
                                <td>${data.cantidad_productos}</td>
                            </tr>
                        </table>
                    </div>
                    
                    <!-- Información del Cliente -->
                    <div class="col-md-6 mb-4">
                        <h6 class="text-success border-bottom pb-2 mb-3">
                            <i class="bi bi-person"></i> Información del Cliente
                        </h6>
                        <table class="table table-sm">
                            <tr>
                                <td class="fw-bold" style="width: 40%;">Nombre:</td>
                                <td>${data.nombre_cliente || 'N/A'}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Email:</td>
                                <td>${data.email_cliente || 'N/A'}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Total Pedido:</td>
                                <td><strong class="text-success">$${data.total_pedido.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
                            </tr>
                        </table>
                    </div>
                </div>
                
                <!-- Productos Devueltos -->
                <div class="mb-3">
                    <h6 class="text-info border-bottom pb-2 mb-3">
                        <i class="bi bi-box-seam"></i> Productos Devueltos
                    </h6>
                    <div class="table-responsive">
                        <table class="table table-sm table-hover">
                            <thead class="table-light">
                                <tr>
                                    <th>Producto</th>
                                    <th>SKU</th>
                                    <th>Cantidad</th>
                                    <th>Precio Unitario</th>
                                    <th>Subtotal</th>
                                    <th>Tipo / Motivo</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${productosHtml}
                            </tbody>
                            <tfoot class="table-light">
                                <tr>
                                    <td colspan="4" class="fw-bold text-end">Total Devolución:</td>
                                    <td colspan="2"><strong>$${totalDevolucion.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
                                </tr>
                            </tfoot>
                        </table>
                    </div>
                </div>
            `;
        })
        .catch(error => {
            console.error('Error:', error);
            modalBody.innerHTML = `
                <div class="alert alert-danger" role="alert">
                    <i class="bi bi-exclamation-triangle"></i> 
                    <strong>Error:</strong> ${error.message || 'No se pudo cargar la información de la devolución'}
                </div>
            `;
        });
}

// Función para abrir modal de cambiar estado
function abrirModalCambiarEstadoDevolucion(idDevolucion, estadoActual) {
    document.getElementById('cambiarEstadoIdDevolucion').value = idDevolucion;
    document.getElementById('cambiarEstadoIdDevolucionDisplay').value = 'Devolución #' + idDevolucion;
    document.getElementById('cambiarEstadoActual').value = estadoActual || 'N/A';
    document.getElementById('cambiarEstadoActualDisplay').value = estadoActual || 'N/A';
    document.getElementById('nuevoEstadoDevolucion').value = '';
    document.getElementById('alertCambiarEstadoContainer').innerHTML = '';

    const modal = new bootstrap.Modal(document.getElementById('modalCambiarEstadoDevolucion'));
    modal.show();
}

// Función para mostrar alertas en el modal de cambiar estado
function showCambiarEstadoAlert(message, type) {
    const alertContainer = document.getElementById('alertCambiarEstadoContainer');
    alertContainer.innerHTML = `
        <div class="alert alert-${type} alert-dismissible fade show" role="alert">
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    `;
}

// Event listeners para botones con data attributes
document.addEventListener('DOMContentLoaded', function () {
    // Botones de ver detalles de devolución
    document.querySelectorAll('.btn-ver-devolucion').forEach(btn => {
        btn.addEventListener('click', function () {
            const id = this.getAttribute('data-devolucion-id');
            verDetallesDevolucion(id);
        });
    });

    // Botones de cambiar estado de devolución
    document.querySelectorAll('.btn-cambiar-estado-devolucion').forEach(btn => {
        btn.addEventListener('click', function () {
            const idDevolucion = this.getAttribute('data-devolucion-id');
            const estadoActual = this.getAttribute('data-estado-actual');
            abrirModalCambiarEstadoDevolucion(idDevolucion, estadoActual);
        });
    });

    // Botón de confirmar cambio de estado
    const btnConfirmarCambiarEstado = document.getElementById('btnConfirmarCambiarEstadoDevolucion');
    if (btnConfirmarCambiarEstado) {
        btnConfirmarCambiarEstado.addEventListener('click', function () {
            const form = document.getElementById('formCambiarEstadoDevolucion');
            
            if (!form.checkValidity()) {
                form.reportValidity();
                return;
            }

            const idDevolucion = document.getElementById('cambiarEstadoIdDevolucion').value;
            const nuevoEstado = document.getElementById('nuevoEstadoDevolucion').value.trim();
            const estadoActual = document.getElementById('cambiarEstadoActual').value;

            if (!nuevoEstado) {
                showCambiarEstadoAlert('Por favor seleccione un nuevo estado', 'danger');
                return;
            }

            if (nuevoEstado === estadoActual) {
                showCambiarEstadoAlert('El nuevo estado debe ser diferente al estado actual', 'warning');
                return;
            }

            // Deshabilitar botón
            const btnConfirmar = document.getElementById('btnConfirmarCambiarEstadoDevolucion');
            const btnOriginalHTML = btnConfirmar.innerHTML;
            btnConfirmar.disabled = true;
            btnConfirmar.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Procesando...';

            // Enviar a la API
            fetch(`/api/admin/devoluciones/${idDevolucion}/actualizar-estado`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    nuevo_estado: nuevoEstado
                })
            })
                .then(response => {
                    if (!response.ok) {
                        throw new Error(`Error HTTP: ${response.status}`);
                    }
                    return response.json().catch(err => {
                        throw new Error('Error al procesar la respuesta del servidor');
                    });
                })
                .then(result => {
                    // Restablecer botón
                    btnConfirmar.disabled = false;
                    btnConfirmar.innerHTML = btnOriginalHTML;

                    if (result.success) {
                        showCambiarEstadoAlert(result.mensaje || 'Estado actualizado exitosamente', 'success');
                        setTimeout(() => {
                            window.location.reload();
                        }, 1500);
                    } else {
                        const errorMsg = result.mensaje || result.error || 'Error al actualizar el estado de la devolución';
                        showCambiarEstadoAlert(errorMsg, 'danger');
                    }
                })
                .catch(err => {
                    console.error('Error:', err);
                    
                    // Restablecer botón en caso de error
                    btnConfirmar.disabled = false;
                    btnConfirmar.innerHTML = btnOriginalHTML;
                    
                    showCambiarEstadoAlert('Error al actualizar el estado: ' + err.message, 'danger');
                });
        });
    }
});
