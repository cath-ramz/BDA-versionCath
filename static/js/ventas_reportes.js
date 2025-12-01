// Cargar KPIs
fetch('/api/ventas/kpis')
    .then(r => r.json())
    .then(data => {
        document.getElementById('kpiVentasMes').textContent = '$' + new Intl.NumberFormat('es-MX').format(data.ventas_mes || 0);
        document.getElementById('kpiClientesRecurrentes').textContent = new Intl.NumberFormat('es-MX').format(data.clientes_atendidos || 0);
    })
    .catch(err => console.error('Error:', err));

// Ticket Promedio
fetch('/api/reporte/ticket-promedio')
    .then(r => r.json())
    .then(data => {
        document.getElementById('kpiTicketPromedio').textContent = '$' + new Intl.NumberFormat('es-MX', { minimumFractionDigits: 2 }).format(data.ticket_promedio || 0);
        document.getElementById('kpiPedidosMes').textContent = new Intl.NumberFormat('es-MX').format(data.numero_total_pedidos || 0);
    })
    .catch(err => console.error('Error:', err));

// Gráfica Ventas Semanales
fetch('/api/ventas/ventas-semanal')
    .then(r => r.json())
    .then(data => {
        Highcharts.chart('chartVentasSemanal', {
            chart: { type: 'area', backgroundColor: 'transparent', height: 300 },
            title: { text: null },
            xAxis: { categories: data.dias || [], title: { text: null } },
            yAxis: { title: { text: 'Ventas ($)' }, min: 0 },
            series: [{
                name: 'Ventas',
                data: data.ventas || [],
                color: '#10b981',
                fillOpacity: 0.3
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        document.getElementById('chartVentasSemanal').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
    });

// Gráfica Top Productos
fetch('/api/ventas/top-productos-mes')
    .then(r => r.json())
    .then(data => {
        if (!data || data.length === 0) {
            document.getElementById('chartTopProductos').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }
        Highcharts.chart('chartTopProductos', {
            chart: { type: 'bar', backgroundColor: 'transparent', height: 300 },
            title: { text: null },
            xAxis: { categories: data.map(p => p.nombre), title: { text: null } },
            yAxis: { title: { text: 'Unidades' }, min: 0 },
            series: [{
                name: 'Unidades Vendidas',
                data: data.map(p => p.unidades_vendidas),
                color: '#3b82f6'
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        document.getElementById('chartTopProductos').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
    });

// Gráfica Ventas por Categoría (datos reales)
fetch('/api/ventas/ventas-por-categoria')
    .then(r => r.json())
    .then(data => {
        if (!data || data.length === 0) {
            document.getElementById('chartVentasCategoria').innerHTML = '<p class="text-center text-muted">No hay datos de ventas por categoría</p>';
            return;
        }

        const colores = ['#3b82f6', '#10b981', '#f59e0b', '#8b5cf6', '#ef4444', '#64748b', '#06b6d4', '#ec4899'];
        const datosGrafica = data.map((cat, i) => ({
            name: cat.nombre,
            y: cat.ingreso,
            color: colores[i % colores.length]
        }));

        Highcharts.chart('chartVentasCategoria', {
            chart: { type: 'pie', backgroundColor: 'transparent', height: 300 },
            title: { text: null },
            tooltip: {
                pointFormat: '<b>${point.y:,.2f}</b> ({point.percentage:.1f}%)'
            },
            plotOptions: {
                pie: {
                    innerSize: '50%',
                    dataLabels: { enabled: true, format: '{point.name}: {point.percentage:.1f}%' }
                }
            },
            series: [{
                name: 'Ingresos',
                colorByPoint: true,
                data: datosGrafica
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error:', err);
        document.getElementById('chartVentasCategoria').innerHTML = '<p class="text-center text-muted">Error cargando datos</p>';
    });
