// Función global de filtrado
function filtrarTabla() {
    const searchInput = document.getElementById('searchInput');
    const filterCategoria = document.getElementById('filterCategoria');
    const filterEstadoStock = document.getElementById('filterEstadoStock');
    const filterSucursal = document.getElementById('filterSucursal');

    if (!searchInput || !filterCategoria || !filterEstadoStock || !filterSucursal) {
        console.warn('Algunos elementos de filtro no se encontraron');
        return;
    }

    const searchText = searchInput.value.toLowerCase();
    const categoria = filterCategoria.value.toLowerCase();
    const estadoStock = filterEstadoStock.value.toLowerCase();
    const sucursalSel = filterSucursal.value;

    const rows = document.querySelectorAll('#tablaInventarioBody tr');
    
    if (rows.length === 0) {
        console.warn('No se encontraron filas en la tabla');
        return;
    }

    rows.forEach(row => {
        const texto = row.textContent.toLowerCase();
        const categoriaRow = row.querySelector('td:nth-child(4)')?.textContent.toLowerCase() || '';
        const estadoRow = row.querySelector('td:nth-child(9)')?.textContent.toLowerCase() || '';
        const sucursalRowId = row.getAttribute('data-sucursal-id') || '';

        const esBajo = estadoRow.includes('bajo');
        const esNormal = estadoRow.includes('normal');

        const matchSearch = !searchText || texto.includes(searchText);
        const matchCategoria = !categoria || categoriaRow.includes(categoria);
        const matchEstado = !estadoStock ||
            (estadoStock === 'bajo' && esBajo) ||
            (estadoStock === 'normal' && esNormal);
        const matchSucursal = !sucursalSel || sucursalRowId === sucursalSel;

        row.style.display = (matchSearch && matchCategoria && matchEstado && matchSucursal)
            ? ''
            : 'none';
    });
}

// Función global para limpiar filtros
function limpiarFiltros() {
    const searchInput = document.getElementById('searchInput');
    const filterCategoria = document.getElementById('filterCategoria');
    const filterEstadoStock = document.getElementById('filterEstadoStock');
    const filterSucursal = document.getElementById('filterSucursal');

    if (searchInput) searchInput.value = '';
    if (filterCategoria) filterCategoria.value = '';
    if (filterEstadoStock) filterEstadoStock.value = '';
    if (filterSucursal) filterSucursal.value = '';
    
    filtrarTabla();
}

// Esperar a que el DOM esté completamente cargado
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initFiltros);
} else {
    // DOM ya está cargado
    initFiltros();
}

function initFiltros() {
    console.log('Inicializando filtros de inventario...');

    // Esperar un poco más para asegurar que la tabla esté renderizada
    setTimeout(() => {
        // Obtener elementos
        const searchInput = document.getElementById('searchInput');
        const filterCategoria = document.getElementById('filterCategoria');
        const filterEstadoStock = document.getElementById('filterEstadoStock');
        const filterSucursal = document.getElementById('filterSucursal');

        // Verificar que los elementos existan
        if (!searchInput || !filterCategoria || !filterEstadoStock || !filterSucursal) {
            console.error('No se encontraron todos los elementos de filtro:', {
                searchInput: !!searchInput,
                filterCategoria: !!filterCategoria,
                filterEstadoStock: !!filterEstadoStock,
                filterSucursal: !!filterSucursal
            });
            return;
        }

        // Agregar event listeners
        searchInput.addEventListener('input', filtrarTabla);
        filterCategoria.addEventListener('change', filtrarTabla);
        filterEstadoStock.addEventListener('change', filtrarTabla);
        filterSucursal.addEventListener('change', filtrarTabla);

        console.log('Event listeners agregados correctamente');

        // Cargar categorías únicas al select
        const selectCat = document.getElementById('filterCategoria');
        if (selectCat) {
            const categorias = new Set();
            const tablaBody = document.getElementById('tablaInventarioBody');
            
            if (!tablaBody) {
                console.warn('No se encontró el elemento tablaInventarioBody');
                return;
            }
            
            const rows = tablaBody.querySelectorAll('tr');
            
            console.log(`Encontradas ${rows.length} filas en la tabla`);
            
            if (rows.length === 0) {
                console.warn('La tabla no tiene filas');
                return;
            }
            
            rows.forEach(row => {
                const catCell = row.querySelector('td:nth-child(4)');
                if (catCell) {
                    const cat = catCell.textContent.trim();
                    if (cat && cat !== '' && cat !== 'Categoría') {
                        categorias.add(cat);
                    }
                }
            });
            
            console.log(`Categorías encontradas: ${Array.from(categorias).join(', ')}`);
            
            // Limpiar opciones existentes (excepto la primera)
            while (selectCat.children.length > 1) {
                selectCat.removeChild(selectCat.lastChild);
            }
            
            // Agregar opciones al select
            categorias.forEach(cat => {
                const opt = document.createElement('option');
                opt.value = cat;
                opt.textContent = cat;
                selectCat.appendChild(opt);
            });
            
            console.log(`Se agregaron ${categorias.size} categorías al select`);
        }

        // Botones "Ajustar" -> abrir modal
        document.querySelectorAll('.btn-ajustar-inventario').forEach(btn => {
            btn.addEventListener('click', function () {
                const sku = this.getAttribute('data-sku');
                const nombre = this.getAttribute('data-nombre');
                if (window.abrirModalAjuste) {
                    window.abrirModalAjuste(sku, nombre);
                }
            });
        });

        // Guardar ajuste
        const btnGuardarAjuste = document.getElementById('btnGuardarAjuste');
        if (btnGuardarAjuste) {
            btnGuardarAjuste.addEventListener('click', function () {
                const form = document.getElementById('formAjusteInventario');
                if (!form.checkValidity()) {
                    form.reportValidity();
                    return;
                }

                const data = {
                    sku: document.getElementById('ajusteSku').value.trim(),
                    nombre_sucursal: document.getElementById('ajusteSucursal').value.trim(),
                    tipo_cambio: document.getElementById('ajusteTipoCambio').value,
                    cantidad: parseInt(document.getElementById('ajusteCantidad').value),
                    motivo: document.getElementById('ajusteMotivo').value.trim()
                };

                if (!data.sku || !data.nombre_sucursal || !data.tipo_cambio || !data.motivo) {
                    showAjusteAlert('Por favor complete todos los campos requeridos', 'danger');
                    return;
                }
                if (data.tipo_cambio === 'Ajuste' && data.cantidad < 0) {
                    showAjusteAlert('La cantidad no puede ser negativa para ajustes', 'danger');
                    return;
                }
                if ((data.tipo_cambio === 'Entrada' || data.tipo_cambio === 'Salida') && data.cantidad <= 0) {
                    showAjusteAlert('La cantidad debe ser positiva para entradas y salidas', 'danger');
                    return;
                }

                const btnGuardar = document.getElementById('btnGuardarAjuste');
                btnGuardar.disabled = true;
                btnGuardar.innerHTML = '<i class="bi bi-hourglass-split"></i> Procesando...';

                fetch('/api/inventario/ajustar', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(data)
                })
                    .then(r => r.json())
                    .then(result => {
                        if (result.success) {
                            showAjusteAlert(result.mensaje, 'success');
                            setTimeout(() => window.location.reload(), 1500);
                        } else {
                            showAjusteAlert(result.mensaje || result.error || 'Error al ajustar el inventario', 'danger');
                            btnGuardar.disabled = false;
                            btnGuardar.innerHTML = '<i class="bi bi-check-circle"></i> Guardar Ajuste';
                        }
                    })
                    .catch(err => {
                        console.error('Error:', err);
                        showAjusteAlert('Error al ajustar el inventario. Por favor, intenta de nuevo.', 'danger');
                        btnGuardar.disabled = false;
                        btnGuardar.innerHTML = '<i class="bi bi-check-circle"></i> Guardar Ajuste';
                    });
            });
        }

        // Función global para abrir modal de ajuste
        window.abrirModalAjuste = function(sku, nombreProducto) {
            document.getElementById('ajusteSku').value = sku;
            document.getElementById('ajusteSkuDisplay').value = sku;
            document.getElementById('ajusteNombreProducto').value = nombreProducto;
            const ajusteSucursal = document.getElementById('ajusteSucursal');
            if (ajusteSucursal) {
                ajusteSucursal.value = ajusteSucursal.getAttribute('value') || '';
            }
            document.getElementById('ajusteTipoCambio').value = '';
            document.getElementById('ajusteCantidad').value = '';
            document.getElementById('ajusteMotivo').value = '';
            document.getElementById('alertAjusteContainer').innerHTML = '';

            const modal = new bootstrap.Modal(document.getElementById('modalAjusteInventario'));
            modal.show();
        };

        function showAjusteAlert(message, type) {
            const alertContainer = document.getElementById('alertAjusteContainer');
            alertContainer.innerHTML = `
                <div class="alert alert-${type} alert-dismissible fade show" role="alert">
                    ${message}
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
            `;
        }

        console.log('Filtros de inventario inicializados correctamente');
    }, 100);
}
