let modalReingreso;
let idDevolucionActual = null;

// Función para ver detalles de devolución
function verDetallesDevolucion(idDevolucion) {
    console.log('=== verDetallesDevolucion llamado ===');
    console.log('ID devolución:', idDevolucion);
    
    // Verificar que Bootstrap esté disponible
    if (typeof bootstrap === 'undefined') {
        console.error('✗ Bootstrap no está disponible');
        alert('Error: Bootstrap no está cargado. Por favor, recarga la página.');
        return;
    }
    
    // Mostrar modal y cargar datos
    const modalElement = document.getElementById('modalVerDevolucion');
    if (!modalElement) {
        console.error('✗ Modal modalVerDevolucion no encontrado');
        alert('Error: No se pudo abrir el modal de detalles. El modal no existe en el DOM.');
        return;
    }
    console.log('✓ Modal encontrado');
    
    const modalBody = document.getElementById('modalDevolucionBody');
    if (!modalBody) {
        console.error('✗ Modal body no encontrado');
        alert('Error: No se pudo encontrar el contenedor del modal');
        return;
    }
    console.log('✓ Modal body encontrado');

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
    try {
        const modal = new bootstrap.Modal(modalElement);
        console.log('✓ Instancia de modal creada');
        modal.show();
        console.log('✓ Modal.show() ejecutado');
    } catch (error) {
        console.error('✗ Error al abrir el modal:', error);
        alert('Error al abrir el modal: ' + error.message);
        return;
    }

    // Cargar datos de la devolución usando el endpoint de admin (inventario puede usar el mismo)
    console.log(`Haciendo fetch a /api/admin/devoluciones/ver/${idDevolucion}`);
    fetch(`/api/admin/devoluciones/ver/${idDevolucion}`)
        .then(response => {
            console.log('Respuesta recibida, status:', response.status);
            if (!response.ok) {
                return response.json().then(data => {
                    throw new Error(data.error || `Error HTTP ${response.status}: No se pudo cargar los detalles de la devolución`);
                });
            }
            return response.json();
        })
        .then(data => {
            console.log('Datos recibidos:', data);
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
                    totalDevolucion += item.subtotal_devolucion || 0;
                    const reembolsoHtml = item.reembolso ? `
                        <tr>
                            <td colspan="6" class="bg-light">
                                <strong>Reembolso:</strong> 
                                $${(item.reembolso.monto_reembolso || 0).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} 
                                - ${item.reembolso.metodo_pago || 'N/A'}
                                ${item.reembolso.fecha_reembolso ? ' - ' + new Date(item.reembolso.fecha_reembolso).toLocaleDateString('es-MX') : ''}
                            </td>
                        </tr>
                    ` : '';
                    return `
                        <tr>
                            <td>${item.nombre_producto || 'N/A'}</td>
                            <td><code class="text-danger">${item.sku || 'N/A'}</code></td>
                            <td>${item.cantidad_devolucion || 0}</td>
                            <td>$${(item.precio_unitario || 0).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
                            <td>$${(item.subtotal_devolucion || 0).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
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
                                <td>${data.cantidad_productos || 0}</td>
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
                                <td><strong class="text-success">$${(data.total_pedido || 0).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
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
            console.error('Error completo:', error);
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
    const idInput = document.getElementById('cambiarEstadoIdDevolucion');
    const idDisplay = document.getElementById('cambiarEstadoIdDevolucionDisplay');
    const estadoInput = document.getElementById('cambiarEstadoActual');
    const estadoDisplay = document.getElementById('cambiarEstadoActualDisplay');
    const nuevoEstadoSelect = document.getElementById('nuevoEstadoDevolucion');
    const alertContainer = document.getElementById('alertCambiarEstadoContainer');
    
    if (!idInput || !idDisplay || !estadoInput || !estadoDisplay || !nuevoEstadoSelect) {
        console.error('Elementos del modal no encontrados');
        alert('Error: No se pudo abrir el modal de cambiar estado');
        return;
    }
    
    idInput.value = idDevolucion;
    idDisplay.value = 'Devolución #' + idDevolucion;
    estadoInput.value = estadoActual || 'N/A';
    estadoDisplay.value = estadoActual || 'N/A';
    nuevoEstadoSelect.value = '';
    if (alertContainer) {
        alertContainer.innerHTML = '';
    }

    const modalElement = document.getElementById('modalCambiarEstadoDevolucion');
    if (!modalElement) {
        console.error('Modal no encontrado');
        alert('Error: No se pudo encontrar el modal');
        return;
    }
    
    const modal = new bootstrap.Modal(modalElement);
    modal.show();
}

// Función para mostrar alertas en el modal de cambiar estado
function showCambiarEstadoAlert(message, type) {
    const alertContainer = document.getElementById('alertCambiarEstadoContainer');
    if (!alertContainer) {
        console.error('Container de alertas no encontrado');
        return;
    }
    alertContainer.innerHTML = `
        <div class="alert alert-${type} alert-dismissible fade show" role="alert">
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    `;
}

function abrirModalReingreso(idDevolucion, tipoDevolucion) {
    idDevolucionActual = idDevolucion;
    const modalReingresoIdElement = document.getElementById('modalReingresoId');
    if (modalReingresoIdElement) {
        modalReingresoIdElement.textContent = '#' + idDevolucion;
    }

    // Validación adicional en frontend
    if (tipoDevolucion === 'Cambio') {
        alert('Las devoluciones de tipo "Cambio" no generan reingreso a inventario.');
        return;
    }

    if (modalReingreso) {
        modalReingreso.show();
    }
}

document.addEventListener('DOMContentLoaded', function () {
    console.log('✓ Script inventario_devoluciones.js cargado');
    
    // Verificar que Bootstrap esté disponible
    if (typeof bootstrap === 'undefined') {
        console.error('✗ Bootstrap no está disponible');
        alert('Error: Bootstrap no está cargado. Por favor, recarga la página.');
        return;
    }
    console.log('✓ Bootstrap disponible');
    
    const modalReingresoElement = document.getElementById('modalReingreso');
    if (modalReingresoElement) {
        modalReingreso = new bootstrap.Modal(modalReingresoElement);
        console.log('✓ Modal de reingreso inicializado');
    }

    // Event listeners para botones "Ver Detalles"
    const botonesVer = document.querySelectorAll('.btn-ver-devolucion');
    console.log(`✓ Botones "Ver Detalles" encontrados: ${botonesVer.length}`);
    
    if (botonesVer.length === 0) {
        console.warn('⚠ No se encontraron botones "Ver Detalles". Reintentando en 500ms...');
        setTimeout(() => {
            const botonesRetry = document.querySelectorAll('.btn-ver-devolucion');
            console.log(`Reintento - Botones encontrados: ${botonesRetry.length}`);
            botonesRetry.forEach((btn, index) => {
                btn.addEventListener('click', function (e) {
                    e.preventDefault();
                    e.stopPropagation();
                    console.log(`Botón "Ver Detalles" #${index + 1} clickeado`);
                    const id = this.getAttribute('data-devolucion-id');
                    console.log(`ID de devolución: ${id}`);
                    if (id) {
                        verDetallesDevolucion(id);
                    } else {
                        console.error('✗ No se encontró el ID de devolución');
                        alert('Error: No se pudo identificar la devolución');
                    }
                });
            });
        }, 500);
    } else {
        botonesVer.forEach((btn, index) => {
            btn.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                console.log(`Botón "Ver Detalles" #${index + 1} clickeado`);
                const id = this.getAttribute('data-devolucion-id');
                console.log(`ID de devolución: ${id}`);
                if (id) {
                    verDetallesDevolucion(id);
                } else {
                    console.error('✗ No se encontró el ID de devolución');
                    alert('Error: No se pudo identificar la devolución');
                }
            });
        });
    }

    // Event listeners para botones "Cambiar Estado"
    const botonesCambiarEstado = document.querySelectorAll('.btn-cambiar-estado-devolucion');
    console.log(`✓ Botones "Cambiar Estado" encontrados: ${botonesCambiarEstado.length}`);
    
    if (botonesCambiarEstado.length === 0) {
        console.warn('⚠ No se encontraron botones "Cambiar Estado". Reintentando en 500ms...');
        setTimeout(() => {
            const botonesRetry = document.querySelectorAll('.btn-cambiar-estado-devolucion');
            console.log(`Reintento - Botones encontrados: ${botonesRetry.length}`);
            botonesRetry.forEach((btn, index) => {
                btn.addEventListener('click', function (e) {
                    e.preventDefault();
                    e.stopPropagation();
                    console.log(`Botón "Cambiar Estado" #${index + 1} clickeado`);
                    const idDevolucion = this.getAttribute('data-devolucion-id');
                    const estadoActual = this.getAttribute('data-estado-actual');
                    console.log(`ID: ${idDevolucion}, Estado: ${estadoActual}`);
                    if (idDevolucion) {
                        abrirModalCambiarEstadoDevolucion(idDevolucion, estadoActual);
                    } else {
                        console.error('✗ No se encontró el ID de devolución');
                        alert('Error: No se pudo identificar la devolución');
                    }
                });
            });
        }, 500);
    } else {
        botonesCambiarEstado.forEach((btn, index) => {
            btn.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                console.log(`Botón "Cambiar Estado" #${index + 1} clickeado`);
                const idDevolucion = this.getAttribute('data-devolucion-id');
                const estadoActual = this.getAttribute('data-estado-actual');
                console.log(`ID: ${idDevolucion}, Estado: ${estadoActual}`);
                if (idDevolucion) {
                    abrirModalCambiarEstadoDevolucion(idDevolucion, estadoActual);
                } else {
                    console.error('✗ No se encontró el ID de devolución');
                    alert('Error: No se pudo identificar la devolución');
                }
            });
        });
    }

    // Event listeners para botones de reingreso
    document.querySelectorAll('.btn-reingresar-devolucion').forEach(btn => {
        btn.addEventListener('click', function () {
            const id = this.getAttribute('data-devolucion-id');
            const tipo = this.getAttribute('data-tipo-devolucion');
            abrirModalReingreso(id, tipo);
        });
    });

    // Botón de confirmar cambio de estado
    const btnConfirmarCambiarEstado = document.getElementById('btnConfirmarCambiarEstadoDevolucion');
    if (btnConfirmarCambiarEstado) {
        btnConfirmarCambiarEstado.addEventListener('click', function () {
            const form = document.getElementById('formCambiarEstadoDevolucion');
            
            if (!form || !form.checkValidity()) {
                if (form) form.reportValidity();
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

            // Enviar a la API (inventario puede usar el mismo endpoint que admin)
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

    // Confirmar reingreso
    const btnConfirmarReingreso = document.getElementById('btnConfirmarReingreso');
    if (btnConfirmarReingreso) {
        btnConfirmarReingreso.addEventListener('click', function () {
            if (!idDevolucionActual) {
                alert('Error: No se ha seleccionado una devolución');
                return;
            }

            const btn = this;
            btn.disabled = true;
            btn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Procesando...';

            fetch(`/api/inventario/devoluciones/${idDevolucionActual}/reingresar`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                }
            })
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        alert(data.mensaje || 'Productos reingresados al inventario exitosamente');
                        if (modalReingreso) modalReingreso.hide();
                        location.reload();
                    } else {
                        alert('Error: ' + (data.mensaje || data.error || 'No se pudo reingresar los productos'));
                        btn.disabled = false;
                        btn.innerHTML = '<i class="bi bi-box-arrow-in-down"></i> Confirmar Reingreso';
                    }
                })
                .catch(error => {
                    console.error('Error:', error);
                    alert('Error al reingresar productos al inventario');
                    btn.disabled = false;
                    btn.innerHTML = '<i class="bi bi-box-arrow-in-down"></i> Confirmar Reingreso';
                });
        });
    }
});
