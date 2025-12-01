// Filtrado de tabla
function initFiltros() {
    const searchInput = document.getElementById('searchInput');
    const filterCategoria = document.getElementById('filterCategoria');
    const filterSucursal = document.getElementById('filterSucursal');
    const filterEstadoStock = document.getElementById('filterEstadoStock');
    
    if (searchInput) {
        searchInput.addEventListener('input', function () {
            filtrarTabla();
        });
    }
    
    if (filterCategoria) {
        filterCategoria.addEventListener('change', function () {
            filtrarTabla();
        });
    }
    
    if (filterSucursal) {
        filterSucursal.addEventListener('change', function () {
            filtrarTabla();
        });
    }
    
    if (filterEstadoStock) {
        filterEstadoStock.addEventListener('change', function () {
            filtrarTabla();
        });
    }
}

function filtrarTabla() {
    const searchText = (document.getElementById('searchInput')?.value || '').toLowerCase();
    const categoria = (document.getElementById('filterCategoria')?.value || '').toLowerCase();
    const sucursal = (document.getElementById('filterSucursal')?.value || '').toLowerCase();
    const estadoStock = (document.getElementById('filterEstadoStock')?.value || '').toLowerCase();
    const rows = document.querySelectorAll('tbody tr');

    rows.forEach(row => {
        const texto = row.textContent.toLowerCase();
        // Columnas: ID(1), Nombre(2), SKU(3), Categoría(4), Sucursal(5), Stock Actual(6), Stock Ideal(7), Unidades Faltantes(8), Estado Stock(9), Valor Inventario(10), Estado(11), Acciones(12)
        const categoriaRow = row.querySelector('td:nth-child(4)')?.textContent.toLowerCase() || '';
        const sucursalRow = row.querySelector('td:nth-child(5)')?.textContent.toLowerCase() || '';
        const estadoStockRow = row.querySelector('td:nth-child(9)')?.textContent.toLowerCase() || '';

        const matchSearch = !searchText || texto.includes(searchText);
        const matchCategoria = !categoria || categoriaRow.includes(categoria);
        const matchSucursal = !sucursal || sucursalRow.includes(sucursal);
        
        // Para estado de stock, comparar el texto normalizado
        let matchEstadoStock = true;
        if (estadoStock) {
            if (estadoStock === 'bajo') {
                matchEstadoStock = estadoStockRow.includes('bajo');
            } else if (estadoStock === 'normal') {
                matchEstadoStock = estadoStockRow.includes('normal');
            }
        }

        row.style.display = (matchSearch && matchCategoria && matchSucursal && matchEstadoStock) ? '' : 'none';
    });
}

// Hacer la función global para que funcione con onclick
window.limpiarFiltros = function() {
    const searchInput = document.getElementById('searchInput');
    const filterCategoria = document.getElementById('filterCategoria');
    const filterSucursal = document.getElementById('filterSucursal');
    const filterEstadoStock = document.getElementById('filterEstadoStock');
    
    if (searchInput) searchInput.value = '';
    if (filterCategoria) filterCategoria.value = '';
    if (filterSucursal) filterSucursal.value = '';
    if (filterEstadoStock) filterEstadoStock.value = '';
    
    filtrarTabla();
};

// Guardar el valor inicial de la sucursal del template
let sucursalInicial = null;

// Cargar categorías y sucursales únicas para los filtros
document.addEventListener('DOMContentLoaded', function () {
    // Inicializar filtros
    initFiltros();
    
    // Guardar el valor inicial de la sucursal cuando se carga la página
    const sucursalField = document.getElementById('ajusteSucursal');
    const sucursalHiddenField = document.getElementById('ajusteSucursalHidden');
    if (sucursalField && sucursalField.value) {
        sucursalInicial = sucursalField.value;
    } else if (sucursalHiddenField && sucursalHiddenField.value) {
        sucursalInicial = sucursalHiddenField.value;
    }
    
    // Cargar categorías únicas
    const categorias = new Set();
    const sucursales = new Set();
    document.querySelectorAll('tbody tr').forEach(row => {
        const categoria = row.querySelector('td:nth-child(4)')?.textContent.trim();
        const sucursal = row.querySelector('td:nth-child(5)')?.textContent.trim();
        if (categoria) categorias.add(categoria);
        if (sucursal && sucursal !== 'Sin sucursal') sucursales.add(sucursal);
    });

    // Poblar filtro de categorías
    const selectCategoria = document.getElementById('filterCategoria');
    if (selectCategoria) {
        categorias.forEach(cat => {
            const option = document.createElement('option');
            option.value = cat;
            option.textContent = cat;
            selectCategoria.appendChild(option);
        });
    }
    
    // Poblar filtro de sucursales
    const selectSucursal = document.getElementById('filterSucursal');
    if (selectSucursal) {
        sucursales.forEach(suc => {
            const option = document.createElement('option');
            option.value = suc;
            option.textContent = suc;
            selectSucursal.appendChild(option);
        });
    }
});

// Funciones para el modal de ajuste
function abrirModalAjuste(sku, nombreProducto, nombreSucursal) {
    document.getElementById('ajusteSku').value = sku;
    document.getElementById('ajusteSkuDisplay').value = sku;
    document.getElementById('ajusteNombreProducto').value = nombreProducto;
    
    // Usar la sucursal del producto específico (de la fila de la tabla)
    const sucursalField = document.getElementById('ajusteSucursal');
    const sucursalHiddenField = document.getElementById('ajusteSucursalHidden');
    
    // Si se pasó una sucursal específica del producto, usarla
    if (nombreSucursal && nombreSucursal.trim() !== '') {
        sucursalField.value = nombreSucursal.trim();
        if (sucursalHiddenField) {
            sucursalHiddenField.value = nombreSucursal.trim();
        }
    } else {
        // Si no hay sucursal del producto, usar la del usuario (fallback)
        if (sucursalInicial) {
            sucursalField.value = sucursalInicial;
            if (sucursalHiddenField) {
                sucursalHiddenField.value = sucursalInicial;
            }
        } else if (sucursalHiddenField && sucursalHiddenField.value) {
            sucursalField.value = sucursalHiddenField.value;
        } else if (!sucursalField.value || sucursalField.value.trim() === '') {
            console.warn('No se encontró valor de sucursal');
        }
    }
    
    document.getElementById('ajusteTipoCambio').value = '';
    document.getElementById('ajusteCantidad').value = '';
    document.getElementById('ajusteMotivo').value = '';
    document.getElementById('alertAjusteContainer').innerHTML = '';

    const modal = new bootstrap.Modal(document.getElementById('modalAjusteInventario'));
    modal.show();
}

// Event listener para botones de ajustar con data attributes
document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.btn-ajustar-inventario').forEach(btn => {
        btn.addEventListener('click', function () {
            const sku = this.getAttribute('data-sku');
            const nombre = this.getAttribute('data-nombre');
            const sucursal = this.getAttribute('data-sucursal');
            abrirModalAjuste(sku, nombre, sucursal);
        });
    });
});

document.getElementById('btnGuardarAjuste').addEventListener('click', function () {
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

    // Validación adicional
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

    // Deshabilitar botón
    const btnGuardar = document.getElementById('btnGuardarAjuste');
    btnGuardar.disabled = true;
    btnGuardar.innerHTML = '<i class="bi bi-hourglass-split"></i> Procesando...';

    // Enviar a la API
    fetch('/api/inventario/ajustar', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
    })
        .then(r => r.json())
        .then(result => {
            if (result.success) {
                showAjusteAlert(result.mensaje, 'success');
                setTimeout(() => {
                    window.location.reload();
                }, 1500);
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

function showAjusteAlert(message, type) {
    const alertContainer = document.getElementById('alertAjusteContainer');
    alertContainer.innerHTML = `
        <div class="alert alert-${type} alert-dismissible fade show" role="alert">
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    `;
}
