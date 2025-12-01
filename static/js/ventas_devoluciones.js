function verDetallesDevolucion(idDevolucion) {
    // Mostrar modal y cargar datos
    const modalElement = document.getElementById('modalVerDevolucion');
    if (!modalElement) {
        console.error('Modal no encontrado');
        alert('Error: No se pudo abrir el modal de detalles');
        return;
    }
    
    const modal = new bootstrap.Modal(modalElement);
    const modalBody = document.getElementById('modalDevolucionBody');

    if (!modalBody) {
        console.error('Modal body no encontrado');
        alert('Error: No se pudo encontrar el contenedor del modal');
        return;
    }

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

    // Cargar datos de la devolución usando el endpoint de ventas
    fetch(`/api/ventas/devoluciones/ver/${idDevolucion}`)
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
                    totalDevolucion += item.subtotal_devolucion || 0;
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
            console.error('Error:', error);
            modalBody.innerHTML = `
                <div class="alert alert-danger" role="alert">
                    <i class="bi bi-exclamation-triangle"></i> 
                    <strong>Error:</strong> ${error.message || 'No se pudo cargar la información de la devolución'}
                </div>
            `;
        });
}

// Event listeners para botones con data attributes
document.addEventListener('DOMContentLoaded', function () {
    console.log('Script ventas_devoluciones.js cargado');
    
    // Verificar que Bootstrap esté disponible
    if (typeof bootstrap === 'undefined') {
        console.error('Bootstrap no está disponible');
        alert('Error: Bootstrap no está cargado. Por favor, recarga la página.');
        return;
    }
    
    // Verificar que el modal exista
    const modalElement = document.getElementById('modalVerDevolucion');
    if (!modalElement) {
        console.error('Modal modalVerDevolucion no encontrado en el DOM');
    } else {
        console.log('Modal encontrado correctamente');
    }
    
    // Botones de ver detalles de devolución
    const botonesVer = document.querySelectorAll('.btn-ver-devolucion');
    console.log('Botones encontrados:', botonesVer.length);
    
    if (botonesVer.length === 0) {
        console.warn('No se encontraron botones con la clase .btn-ver-devolucion');
        // Intentar nuevamente después de un pequeño delay por si la tabla se carga dinámicamente
        setTimeout(() => {
            const botonesRetry = document.querySelectorAll('.btn-ver-devolucion');
            console.log('Botones encontrados en retry:', botonesRetry.length);
            if (botonesRetry.length > 0) {
                botonesRetry.forEach(btn => {
                    btn.addEventListener('click', function (e) {
                        e.preventDefault();
                        e.stopPropagation();
                        const id = this.getAttribute('data-devolucion-id');
                        console.log('Botón clickeado, ID devolución:', id);
                        if (id) {
                            verDetallesDevolucion(id);
                        } else {
                            console.error('No se encontró el ID de devolución');
                            alert('Error: No se pudo identificar la devolución');
                        }
                    });
                });
            }
        }, 500);
    }
    
    botonesVer.forEach(btn => {
        btn.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            const id = this.getAttribute('data-devolucion-id');
            console.log('Botón clickeado, ID devolución:', id);
            if (id) {
                verDetallesDevolucion(id);
            } else {
                console.error('No se encontró el ID de devolución');
                alert('Error: No se pudo identificar la devolución');
            }
        });
    });
});

