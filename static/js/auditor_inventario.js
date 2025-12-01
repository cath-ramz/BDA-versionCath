function filtrarTabla() {
    const searchText = document.getElementById('searchInput').value.toLowerCase();
    const categoria = document.getElementById('filterCategoria').value.toLowerCase();
    const estadoStock = document.getElementById('filterEstadoStock').value.toLowerCase();
    const rows = document.querySelectorAll('tbody tr');

    rows.forEach(row => {
        const texto = row.textContent.toLowerCase();
        // Columnas: ID(1), Nombre(2), SKU(3), Categoría(4), Sucursal(5), Stock Actual(6), Stock Ideal(7), Unidades Faltantes(8), Estado Stock(9), Valor Inventario(10), Estado(11)
        const categoriaRow = row.querySelector('td:nth-child(4)')?.textContent.toLowerCase() || '';
        const estadoRow = row.querySelector('td:nth-child(9)')?.textContent.toLowerCase() || ''; // Estado Stock está en la columna 9

        const esBajo = estadoRow.includes('bajo');
        const esNormal = estadoRow.includes('normal');
        const esCritico = estadoRow.includes('crítico') || estadoRow.includes('critico');

        const matchSearch = !searchText || texto.includes(searchText);
        const matchCategoria = !categoria || categoriaRow.includes(categoria);
        
        // Lógica de filtrado de estado de stock
        let matchEstado = true;
        if (estadoStock) {
            if (estadoStock === 'bajo') {
                matchEstado = esBajo;
            } else if (estadoStock === 'normal') {
                matchEstado = esNormal && !esBajo && !esCritico; // Normal solo si no es bajo ni crítico
            } else if (estadoStock === 'critico' || estadoStock === 'crítico') {
                matchEstado = esCritico;
            }
        }

        row.style.display = (matchSearch && matchCategoria && matchEstado) ? '' : 'none';
    });
}

function limpiarFiltros() {
    document.getElementById('searchInput').value = '';
    document.getElementById('filterCategoria').value = '';
    document.getElementById('filterEstadoStock').value = '';
    filtrarTabla();
}

// Event listeners
document.getElementById('searchInput').addEventListener('input', filtrarTabla);
document.getElementById('filterCategoria').addEventListener('change', filtrarTabla);
document.getElementById('filterEstadoStock').addEventListener('change', filtrarTabla);

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
