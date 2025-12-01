document.getElementById('searchInput').addEventListener('input', filtrarTabla);
document.getElementById('filterCategoria').addEventListener('change', filtrarTabla);
document.getElementById('filterEstado').addEventListener('change', filtrarTabla);

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

document.addEventListener('DOMContentLoaded', function() {
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
