// Funciones para editar y ver detalles
function editarProducto(id) {
    window.location.href = '/admin/productos/editar/' + id;
}

function verDetalles(id) {
    // Mostrar modal y cargar datos
    const modal = new bootstrap.Modal(document.getElementById('modalVerDetalles'));
    const modalBody = document.getElementById('modalDetallesBody');
    const btnEditar = document.getElementById('btnEditarDesdeModal');

    // Mostrar loading
    modalBody.innerHTML = `
        <div class="text-center py-4">
            <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">Cargando...</span>
            </div>
            <p class="mt-2 text-muted">Cargando información del producto...</p>
        </div>
    `;

    // Ocultar botón editar mientras carga
    btnEditar.style.display = 'none';

    // Abrir modal
    modal.show();

    // Cargar datos del producto
    fetch(`/api/productos/ver/${id}`)
        .then(response => {
            if (!response.ok) {
                throw new Error('Error al cargar los detalles del producto');
            }
            return response.json();
        })
        .then(data => {
            // Calcular precio con descuento
            const precioOriginal = data.precio_unitario;
            const descuento = data.descuento_producto || 0;
            const precioFinal = precioOriginal * (1 - descuento / 100);
            const margenGanancia = precioFinal - data.costo_unitario;
            const porcentajeMargen = data.costo_unitario > 0 ? ((margenGanancia / data.costo_unitario) * 100).toFixed(2) : 0;

            // Formatear inventario por sucursal
            let inventarioHtml = '';
            if (data.inventario && data.inventario.length > 0) {
                inventarioHtml = data.inventario.map(item => {
                    const estadoStock = item.unidades_faltantes > 3 ? 'danger' :
                        item.unidades_faltantes > 0 ? 'warning' : 'success';
                    const textoEstado = item.unidades_faltantes > 3 ? 'Crítico' :
                        item.unidades_faltantes > 0 ? 'Bajo' : 'Normal';
                    return `
                        <tr>
                            <td><strong>${item.sucursal}</strong></td>
                            <td>${item.stock_actual}</td>
                            <td>${item.stock_ideal}</td>
                            <td>
                                <span class="badge bg-${estadoStock}">${textoEstado}</span>
                                ${item.unidades_faltantes > 0 ? `<span class="text-muted">(${item.unidades_faltantes} faltantes)</span>` : ''}
                            </td>
                        </tr>
                    `;
                }).join('');
            } else {
                inventarioHtml = '<tr><td colspan="4" class="text-center text-muted">No hay inventario registrado</td></tr>';
            }

            // Construir HTML del modal
            modalBody.innerHTML = `
                <div class="row">
                    <!-- Información Básica -->
                    <div class="col-md-6 mb-4">
                        <h6 class="text-primary border-bottom pb-2 mb-3">
                            <i class="bi bi-info-circle"></i> Información Básica
                        </h6>
                        <table class="table table-sm">
                            <tr>
                                <td class="fw-bold" style="width: 40%;">ID:</td>
                                <td>#${data.id_producto}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">SKU:</td>
                                <td><code class="text-danger">${data.sku}</code></td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Nombre:</td>
                                <td>${data.nombre_producto}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Categoría:</td>
                                <td>${data.nombre_categoria}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Material:</td>
                                <td>${data.material}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Género:</td>
                                <td>${data.genero_producto}</td>
                            </tr>
                            ${data.talla ? `<tr><td class="fw-bold">Talla:</td><td>${data.talla}</td></tr>` : ''}
                            ${data.kilataje ? `<tr><td class="fw-bold">Kilataje:</td><td>${data.kilataje}</td></tr>` : ''}
                            ${data.ley ? `<tr><td class="fw-bold">Ley:</td><td>${data.ley}</td></tr>` : ''}
                            <tr>
                                <td class="fw-bold">Estado:</td>
                                <td>
                                    ${data.activo_producto
                    ? '<span class="badge bg-success">Activo</span>'
                    : '<span class="badge bg-secondary">Inactivo</span>'}
                                </td>
                            </tr>
                        </table>
                    </div>
                    
                    <!-- Información Financiera -->
                    <div class="col-md-6 mb-4">
                        <h6 class="text-success border-bottom pb-2 mb-3">
                            <i class="bi bi-currency-dollar"></i> Información Financiera
                        </h6>
                        <table class="table table-sm">
                            <tr>
                                <td class="fw-bold" style="width: 40%;">Precio Unitario:</td>
                                <td><strong class="text-success">$${precioOriginal.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
                            </tr>
                            ${descuento > 0 ? `
                            <tr>
                                <td class="fw-bold">Descuento:</td>
                                <td><span class="text-danger">${descuento}%</span></td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Precio Final:</td>
                                <td><strong class="text-success">$${precioFinal.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></td>
                            </tr>
                            ` : ''}
                            <tr>
                                <td class="fw-bold">Costo Unitario:</td>
                                <td>$${data.costo_unitario.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
                            </tr>
                            <tr>
                                <td class="fw-bold">Margen de Ganancia:</td>
                                <td>
                                    <strong class="text-success">$${margenGanancia.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
                                    <span class="text-muted">(${porcentajeMargen}%)</span>
                                </td>
                            </tr>
                        </table>
                    </div>
                </div>
                
                <!-- Inventario por Sucursal -->
                <div class="mb-3">
                    <h6 class="text-info border-bottom pb-2 mb-3">
                        <i class="bi bi-box-seam"></i> Inventario por Sucursal
                    </h6>
                    <div class="table-responsive">
                        <table class="table table-sm table-hover">
                            <thead class="table-light">
                                <tr>
                                    <th>Sucursal</th>
                                    <th>Stock Actual</th>
                                    <th>Stock Ideal</th>
                                    <th>Estado</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${inventarioHtml}
                            </tbody>
                            <tfoot class="table-light">
                                <tr>
                                    <td class="fw-bold">Total:</td>
                                    <td><strong>${data.stock_total}</strong></td>
                                    <td><strong>${data.stock_ideal_total}</strong></td>
                                    <td>
                                        ${data.unidades_faltantes_total > 0
                    ? `<span class="badge bg-warning">${data.unidades_faltantes_total} faltantes</span>`
                    : '<span class="badge bg-success">Completo</span>'}
                                    </td>
                                </tr>
                            </tfoot>
                        </table>
                    </div>
                </div>
            `;

            // Mostrar botón editar
            btnEditar.style.display = 'inline-block';
            btnEditar.onclick = () => {
                modal.hide();
                window.location.href = `/admin/productos/editar/${id}`;
            };
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

// Event listeners para botones con data attributes
document.addEventListener('DOMContentLoaded', function () {
    // Botones de editar producto
    document.querySelectorAll('.btn-editar-producto').forEach(btn => {
        btn.addEventListener('click', function () {
            const id = this.getAttribute('data-producto-id');
            editarProducto(id);
        });
    });

    // Botones de ver detalles
    document.querySelectorAll('.btn-ver-detalles').forEach(btn => {
        btn.addEventListener('click', function () {
            const id = this.getAttribute('data-producto-id');
            verDetalles(id);
        });
    });
});

// Filtrado de tabla
document.getElementById('searchInput').addEventListener('input', function () {
    filtrarTabla();
});

document.getElementById('filterCategoria').addEventListener('change', function () {
    filtrarTabla();
});

document.getElementById('filterEstado').addEventListener('change', function () {
    filtrarTabla();
});

function filtrarTabla() {
    const searchText = document.getElementById('searchInput').value.toLowerCase();
    const categoria = document.getElementById('filterCategoria').value.toLowerCase();
    const estado = document.getElementById('filterEstado').value;
    const rows = document.querySelectorAll('tbody tr');

    rows.forEach(row => {
        const texto = row.textContent.toLowerCase();
        const categoriaRow = row.querySelector('td:nth-child(4)')?.textContent.toLowerCase() || '';
        const estadoRow = row.querySelector('td:nth-child(9)')?.textContent || '';
        const esActivo = estadoRow.includes('Activo');

        const matchSearch = !searchText || texto.includes(searchText);
        const matchCategoria = !categoria || categoriaRow.includes(categoria);
        const matchEstado = !estado || (estado === '1' && esActivo) || (estado === '0' && !esActivo);

        row.style.display = (matchSearch && matchCategoria && matchEstado) ? '' : 'none';
    });
}

function limpiarFiltros() {
    document.getElementById('searchInput').value = '';
    document.getElementById('filterCategoria').value = '';
    document.getElementById('filterEstado').value = '';
    filtrarTabla();
}

// Cargar categorías únicas para el filtro
document.addEventListener('DOMContentLoaded', function () {
    const categorias = new Set();
    document.querySelectorAll('tbody tr').forEach(row => {
        const categoria = row.querySelector('td:nth-child(4)')?.textContent.trim();
        if (categoria) categorias.add(categoria);
    });

    const select = document.getElementById('filterCategoria');
    categorias.forEach(cat => {
        const option = document.createElement('option');
        option.value = cat;
        option.textContent = cat;
        select.appendChild(option);
    });
});
