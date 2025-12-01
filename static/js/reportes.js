// Cargar todos los reportes automáticamente al cargar la página
document.addEventListener('DOMContentLoaded', function() {
    console.log('Cargando reportes...');
    cargarTodosLosReportes();
});

function cargarTodosLosReportes() {
    // Cargar todos los reportes de forma asíncrona
    Promise.allSettled([
        Promise.resolve(cargarResumenEjecutivo()).catch(err => { console.error('Error en resumen:', err); return Promise.resolve(); }),
        Promise.resolve(cargarVentasMes()).catch(err => { console.error('Error en ventas mes:', err); return Promise.resolve(); }),
        Promise.resolve(cargarVentasCategoria()).catch(err => { console.error('Error en ventas categoría:', err); return Promise.resolve(); }),
        Promise.resolve(cargarTopProductos()).catch(err => { console.error('Error en top productos:', err); return Promise.resolve(); }),
        Promise.resolve(cargarClientesFrecuentes()).catch(err => { console.error('Error en clientes frecuentes:', err); return Promise.resolve(); }),
        Promise.resolve(cargarClientesVIP()).catch(err => { console.error('Error en clientes VIP:', err); return Promise.resolve(); }),
        Promise.resolve(cargarDevoluciones()).catch(err => { console.error('Error en devoluciones:', err); return Promise.resolve(); }),
        Promise.resolve(cargarInventarioBajoStock()).catch(err => { console.error('Error en inventario:', err); return Promise.resolve(); }),
        Promise.resolve(cargarProductosRentables()).catch(err => { console.error('Error en productos rentables:', err); return Promise.resolve(); }),
        Promise.resolve(cargarFacturacionDiaria()).catch(err => { console.error('Error en facturación:', err); return Promise.resolve(); })
    ]).then(() => {
        console.log('Todos los reportes cargados');
    });
}

// Resumen Ejecutivo - Cargar todos los datos
function cargarResumenEjecutivo() {
    // Sin parámetros de fecha, cargar todos los datos
    return fetch('/api/reporte/resumen-ejecutivo')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('Datos resumen ejecutivo:', data);
            
            const ingresosEl = document.getElementById('kpiIngresosTotales');
            const pedidosEl = document.getElementById('kpiTotalPedidos');
            const ticketEl = document.getElementById('kpiTicketPromedio');
            const devolucionEl = document.getElementById('kpiTasaDevolucion');
            
            if (ingresosEl) {
                ingresosEl.textContent = 
                    '$' + new Intl.NumberFormat('es-MX', {minimumFractionDigits: 2, maximumFractionDigits: 2}).format(data.ingresos_totales || 0);
            }
            if (pedidosEl) {
                pedidosEl.textContent = 
                    new Intl.NumberFormat('es-MX').format(data.total_pedidos || 0);
            }
            if (ticketEl) {
                ticketEl.textContent = 
                    '$' + new Intl.NumberFormat('es-MX', {minimumFractionDigits: 2, maximumFractionDigits: 2}).format(data.ticket_promedio || 0);
            }
            if (devolucionEl) {
                devolucionEl.textContent = 
                    (data.tasa_devolucion || 0).toFixed(1) + '%';
            }
        })
        .catch(err => {
            console.error('Error cargando resumen ejecutivo:', err);
            // Mostrar error en los KPIs
            const ingresosEl = document.getElementById('kpiIngresosTotales');
            const pedidosEl = document.getElementById('kpiTotalPedidos');
            const ticketEl = document.getElementById('kpiTicketPromedio');
            const devolucionEl = document.getElementById('kpiTasaDevolucion');
            
            if (ingresosEl) ingresosEl.textContent = 'Error';
            if (pedidosEl) pedidosEl.textContent = 'Error';
            if (ticketEl) ticketEl.textContent = 'Error';
            if (devolucionEl) devolucionEl.textContent = 'Error';
            
            return Promise.resolve(); // Resolver para no bloquear otras cargas
        });
}

// Ventas por Año
function cargarVentasMes() {
    return fetch('/api/reporte/ventas-mes')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('Datos ventas por año:', data);
            
            if (!data || data.length === 0) {
                console.warn('No hay datos de ventas por año');
                document.getElementById('chartVentasMes').innerHTML = 
                    '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
                return;
            }
            
            const anos = data.map(d => d.mes || d.anio || 'N/A');
            const totales = data.map(d => parseFloat(d.total || d.total_anio || 0));
            
            Highcharts.chart('chartVentasMes', {
                chart: { type: 'column' },
                title: { text: 'Ventas por Año (Últimos 5 Años)' },
                xAxis: { 
                    categories: anos,
                    title: { text: 'Año' }
                },
                yAxis: { title: { text: 'Monto ($)' } },
                series: [{
                    name: 'Ventas',
                    data: totales,
                    color: '#3498db'
                }],
                tooltip: {
                    pointFormat: '<b>${point.y:,.2f}</b>'
                },
                plotOptions: {
                    column: {
                        dataLabels: {
                            enabled: true,
                            format: '${point.y:,.0f}'
                        }
                    }
                }
            });
        })
        .catch(err => {
            console.error('Error cargando ventas por año:', err);
            const chartEl = document.getElementById('chartVentasMes');
            if (chartEl) {
                chartEl.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            }
            return Promise.resolve();
        });
}

// Ventas por Categoría
function cargarVentasCategoria() {
    return fetch('/api/reporte/margen-categoria')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('Datos ventas por categoría:', data);
            
            if (!data || data.length === 0) {
                console.warn('No hay datos de ventas por categoría');
                document.getElementById('chartVentasCategoria').innerHTML = 
                    '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
                document.getElementById('chartVentasCategoriaPie').innerHTML = 
                    '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
                return;
            }
            
            const categorias = data.map(d => d.categoria || d.nombre_categoria || 'N/A');
            const ventas = data.map(d => parseFloat(d.total_ventas || d.ventas || d.ingreso_total || 0));
            
            // Gráfica de barras
            Highcharts.chart('chartVentasCategoria', {
                chart: { type: 'bar' },
                title: { text: 'Ventas por Categoría' },
                xAxis: { categories: categorias },
                yAxis: { title: { text: 'Monto ($)' } },
                series: [{
                    name: 'Ventas',
                    data: ventas,
                    color: '#9b59b6'
                }],
                tooltip: {
                    pointFormat: '<b>${point.y:,.2f}</b>'
                }
            });
            
            // Gráfica de pastel
            Highcharts.chart('chartVentasCategoriaPie', {
                chart: { type: 'pie' },
                title: { text: 'Distribución de Ventas por Categoría' },
                series: [{
                    name: 'Ventas',
                    data: categorias.map((cat, i) => ({ name: cat, y: ventas[i] }))
                }],
                tooltip: {
                    pointFormat: '<b>${point.y:,.2f}</b> ({point.percentage:.1f}%)'
                }
            });
        })
        .catch(err => {
            console.error('Error cargando ventas por categoría:', err);
            const chart1 = document.getElementById('chartVentasCategoria');
            const chart2 = document.getElementById('chartVentasCategoriaPie');
            if (chart1) chart1.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            if (chart2) chart2.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            return Promise.resolve();
        });
}

// Top Productos
function cargarTopProductos() {
    const n = parseInt(document.getElementById('topNProductos')?.value) || 5;
    // Sin parámetros de fecha, cargar todos los datos
    const params = new URLSearchParams({
        n: n
    });
    
    return fetch(`/api/reporte/top-productos?${params}`)
        .then(r => r.json())
        .then(data => {
            const nombres = data.map(d => d.nombre);
            const cantidades = data.map(d => d.cantidad_vendida);
            
            Highcharts.chart('chartTopProductos', {
                chart: { type: 'column' },
                title: { text: `Top ${n} Productos Más Vendidos` },
                xAxis: { categories: nombres },
                yAxis: { title: { text: 'Cantidad Vendida' } },
                series: [{
                    name: 'Unidades Vendidas',
                    data: cantidades,
                    color: '#e74c3c'
                }],
                tooltip: {
                    pointFormat: '<b>{point.y}</b> unidades'
                }
            });
            
            // Tabla
            let tablaHtml = `
                <table class="table table-hover table-report">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>Producto</th>
                            <th>Cantidad Vendida</th>
                        </tr>
                    </thead>
                    <tbody>
            `;
            data.forEach((item, index) => {
                tablaHtml += `
                    <tr>
                        <td>${index + 1}</td>
                        <td>${item.nombre}</td>
                        <td><strong>${item.cantidad_vendida}</strong> unidades</td>
                    </tr>
                `;
            });
            tablaHtml += '</tbody></table>';
            document.getElementById('tablaTopProductos').innerHTML = tablaHtml;
        })
        .catch(err => {
            console.error('Error cargando top productos:', err);
            throw err;
        });
}

// Clientes Frecuentes - Cargar todos los datos
function cargarClientesFrecuentes() {
    // Sin parámetros de fecha, cargar todos los datos
    const params = new URLSearchParams({
        limite: 10
    });
    
    return fetch(`/api/reporte/clientes-frecuentes?${params}`)
        .then(r => r.json())
        .then(data => {
            let tablaHtml = `
                <table class="table table-hover table-report">
                    <thead>
                        <tr>
                            <th>Cliente</th>
                            <th>Total Pedidos</th>
                            <th>Total Gastado</th>
                        </tr>
                    </thead>
                    <tbody>
            `;
            data.forEach(item => {
                tablaHtml += `
                    <tr>
                        <td>${item.nombre}</td>
                        <td><span class="badge bg-primary">${item.total_pedidos}</span></td>
                        <td>$${new Intl.NumberFormat('es-MX', {minimumFractionDigits: 2}).format(item.total_gastado)}</td>
                    </tr>
                `;
            });
            tablaHtml += '</tbody></table>';
            document.getElementById('tablaClientesFrecuentes').innerHTML = tablaHtml;
        })
        .catch(err => {
            console.error('Error cargando clientes frecuentes:', err);
            throw err;
        });
}

// Clientes VIP - Cargar todos los datos
function cargarClientesVIP() {
    // Sin parámetros de fecha, cargar todos los datos
    const params = new URLSearchParams({
        limite: 10
    });
    
    return fetch(`/api/reporte/clientes-vip?${params}`)
        .then(r => r.json())
        .then(data => {
            let tablaHtml = `
                <table class="table table-hover table-report">
                    <thead>
                        <tr>
                            <th>Cliente</th>
                            <th>Total Gastado</th>
                            <th>Total Pedidos</th>
                        </tr>
                    </thead>
                    <tbody>
            `;
            data.forEach(item => {
                tablaHtml += `
                    <tr>
                        <td>${item.nombre}</td>
                        <td><strong class="text-success">$${new Intl.NumberFormat('es-MX', {minimumFractionDigits: 2}).format(item.total_gastado)}</strong></td>
                        <td><span class="badge bg-info">${item.total_pedidos}</span></td>
                    </tr>
                `;
            });
            tablaHtml += '</tbody></table>';
            document.getElementById('tablaClientesVIP').innerHTML = tablaHtml;
        })
        .catch(err => {
            console.error('Error cargando clientes VIP:', err);
            throw err;
        });
}

// Devoluciones - Cargar todos los datos
function cargarDevoluciones() {
    // Sin parámetros de fecha, cargar todos los datos
    return fetch('/api/reporte/devoluciones-analisis')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('Datos devoluciones:', data);
            
            // Gráfica de devoluciones por año
            if (data.devoluciones_anio && data.devoluciones_anio.length > 0) {
                const anos = data.devoluciones_anio.map(d => d.anio.toString());
                const cantidades = data.devoluciones_anio.map(d => d.cantidad);
                const totales = data.devoluciones_anio.map(d => d.total);
                
                Highcharts.chart('chartDevolucionesMotivo', {
                    chart: { type: 'column' },
                    title: { text: 'Devoluciones por Año (Últimos 5 Años)' },
                    xAxis: { 
                        categories: anos,
                        title: { text: 'Año' }
                    },
                    yAxis: { 
                        title: { text: 'Cantidad de Devoluciones' }
                    },
                    series: [{
                        name: 'Cantidad',
                        data: cantidades,
                        color: '#e67e22'
                    }],
                    tooltip: {
                        pointFormat: '<b>{point.y}</b> devoluciones'
                    },
                    plotOptions: {
                        column: {
                            dataLabels: {
                                enabled: true
                            }
                        }
                    }
                });
                
                Highcharts.chart('chartDevolucionesTipo', {
                    chart: { type: 'column' },
                    title: { text: 'Monto de Devoluciones por Año (Últimos 5 Años)' },
                    xAxis: { 
                        categories: anos,
                        title: { text: 'Año' }
                    },
                    yAxis: { 
                        title: { text: 'Monto ($)' }
                    },
                    series: [{
                        name: 'Total',
                        data: totales,
                        color: '#fa709a'
                    }],
                    tooltip: {
                        pointFormat: '<b>${point.y:,.2f}</b>'
                    },
                    plotOptions: {
                        column: {
                            dataLabels: {
                                enabled: true,
                                format: '${point.y:,.0f}'
                            }
                        }
                    }
                });
            } else {
                document.getElementById('chartDevolucionesMotivo').innerHTML = 
                    '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
                document.getElementById('chartDevolucionesTipo').innerHTML = 
                    '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
            }
            
            // Tabla de devoluciones
            if (data.devoluciones && data.devoluciones.length > 0) {
                let tablaHtml = `
                    <table class="table table-hover table-report">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Fecha</th>
                                <th>Estado</th>
                                <th>Productos</th>
                                <th>Total</th>
                            </tr>
                        </thead>
                        <tbody>
                `;
                data.devoluciones.forEach(item => {
                    const estadoBadge = item.estado === 'Completado' ? 'bg-success' : 
                                       item.estado === 'Autorizado' ? 'bg-info' : 
                                       item.estado === 'Rechazado' ? 'bg-danger' : 'bg-warning';
                    tablaHtml += `
                        <tr>
                            <td>#${item.id}</td>
                            <td>${new Date(item.fecha).toLocaleDateString('es-MX')}</td>
                            <td><span class="badge ${estadoBadge}">${item.estado}</span></td>
                            <td>${item.cantidad_productos}</td>
                            <td>$${new Intl.NumberFormat('es-MX', {minimumFractionDigits: 2}).format(item.total)}</td>
                        </tr>
                    `;
                });
                tablaHtml += '</tbody></table>';
                document.getElementById('tablaDevoluciones').innerHTML = tablaHtml;
            } else {
                document.getElementById('tablaDevoluciones').innerHTML = 
                    '<p class="text-muted">No hay devoluciones registradas</p>';
            }
        })
        .catch(err => {
            console.error('Error cargando devoluciones:', err);
            const chart1 = document.getElementById('chartDevolucionesMotivo');
            const chart2 = document.getElementById('chartDevolucionesTipo');
            if (chart1) chart1.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            if (chart2) chart2.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            return Promise.resolve();
        });
}

// Inventario Bajo Stock
function cargarInventarioBajoStock() {
    return fetch('/api/reporte/inventario-bajo-stock')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('Datos inventario bajo stock:', data);
            
            // Verificar si data es un array o tiene un error
            if (data.error) {
                console.error('Error en respuesta:', data.error);
                document.getElementById('tablaBajoStock').innerHTML = 
                    '<p class="text-danger">Error al cargar los datos</p>';
                return;
            }
            
            if (!data || data.length === 0) {
                document.getElementById('tablaBajoStock').innerHTML = 
                    '<p class="text-muted">No hay productos con bajo stock</p>';
                return;
            }
            
            let tablaHtml = `
                <table class="table table-hover table-report">
                    <thead>
                        <tr>
                            <th>Producto</th>
                            <th>SKU</th>
                            <th>Stock Actual</th>
                            <th>Stock Mínimo</th>
                            <th>Estado</th>
                        </tr>
                    </thead>
                    <tbody>
            `;
            data.forEach(item => {
                const stockActual = parseInt(item.stock_actual || 0);
                const stockMinimo = parseInt(item.stock_minimo || 0);
                const estado = stockActual < stockMinimo ? 
                    '<span class="badge bg-danger">Crítico</span>' : 
                    '<span class="badge bg-warning">Bajo</span>';
                tablaHtml += `
                    <tr>
                        <td>${item.nombre || 'N/A'}</td>
                        <td><code>${item.sku || 'N/A'}</code></td>
                        <td>${stockActual}</td>
                        <td>${stockMinimo}</td>
                        <td>${estado}</td>
                    </tr>
                `;
            });
            tablaHtml += '</tbody></table>';
            document.getElementById('tablaBajoStock').innerHTML = tablaHtml;
        })
        .catch(err => {
            console.error('Error cargando inventario bajo stock:', err);
            const tablaEl = document.getElementById('tablaBajoStock');
            if (tablaEl) {
                tablaEl.innerHTML = '<p class="text-danger">Error al cargar los datos</p>';
            }
            return Promise.resolve();
        });
}

// Productos Rentables - Cargar todos los datos
function cargarProductosRentables() {
    // Sin parámetros de fecha, cargar todos los datos
    const params = new URLSearchParams({
        limite: 10
    });
    
    return fetch(`/api/reporte/productos-rentables?${params}`)
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('Datos productos rentables:', data);
            
            // Verificar si data es un array o tiene un error
            if (data.error) {
                console.error('Error en respuesta:', data.error);
                document.getElementById('tablaProductosRentables').innerHTML = 
                    '<p class="text-danger">Error al cargar los datos</p>';
                return;
            }
            
            if (!data || data.length === 0) {
                document.getElementById('tablaProductosRentables').innerHTML = 
                    '<p class="text-muted">No hay productos rentables disponibles</p>';
                return;
            }
            
            let tablaHtml = `
                <table class="table table-hover table-report">
                    <thead>
                        <tr>
                            <th>Producto</th>
                            <th>SKU</th>
                            <th>Unidades Vendidas</th>
                            <th>Ingresos Totales</th>
                            <th>Precio Promedio</th>
                        </tr>
                    </thead>
                    <tbody>
            `;
            data.forEach(item => {
                tablaHtml += `
                    <tr>
                        <td>${item.nombre || 'N/A'}</td>
                        <td><code>${item.sku || 'N/A'}</code></td>
                        <td>${item.unidades_vendidas || 0}</td>
                        <td><strong class="text-success">$${new Intl.NumberFormat('es-MX', {minimumFractionDigits: 2}).format(item.ingresos_totales || 0)}</strong></td>
                        <td>$${new Intl.NumberFormat('es-MX', {minimumFractionDigits: 2}).format(item.precio_promedio || 0)}</td>
                    </tr>
                `;
            });
            tablaHtml += '</tbody></table>';
            document.getElementById('tablaProductosRentables').innerHTML = tablaHtml;
        })
        .catch(err => {
            console.error('Error cargando productos rentables:', err);
            const tablaEl = document.getElementById('tablaProductosRentables');
            if (tablaEl) {
                tablaEl.innerHTML = '<p class="text-danger">Error al cargar los datos</p>';
            }
            return Promise.resolve();
        });
}

// Facturación Diaria - Últimos 30 días por defecto
function cargarFacturacionDiaria() {
    // Mostrar últimos 30 días por defecto
    const params = new URLSearchParams({
        dias: 30
    });
    
    return fetch(`/api/reporte/facturacion-diaria?${params}`)
        .then(r => r.json())
        .then(data => {
            const fechas = data.map(d => d.fecha);
            const totales = data.map(d => parseFloat(d.total_facturado || 0));
            
            Highcharts.chart('chartFacturacionDiaria', {
                chart: { type: 'line' },
                title: { text: 'Facturación Diaria' },
                xAxis: { categories: fechas },
                yAxis: { title: { text: 'Monto ($)' } },
                series: [{
                    name: 'Facturación',
                    data: totales,
                    color: '#27ae60'
                }],
                tooltip: {
                    pointFormat: '<b>${point.y:,.2f}</b>'
                }
            });
        })
        .catch(err => {
            console.error('Error cargando facturación diaria:', err);
            throw err;
        });
}

