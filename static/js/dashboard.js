// Cargar KPIs
fetch('/api/reporte/kpis')
    .then(r => r.json())
    .then(data => {
        document.getElementById('kpiVentas').textContent = '$' + new Intl.NumberFormat('es-MX').format(data.total_ventas);
        document.getElementById('kpiProductos').textContent = new Intl.NumberFormat('es-MX').format(data.total_productos);
        document.getElementById('kpiPedidos').textContent = new Intl.NumberFormat('es-MX').format(data.total_pedidos);
        document.getElementById('kpiClientes').textContent = new Intl.NumberFormat('es-MX').format(data.total_clientes);
    })
    .catch(err => console.error('Error cargando KPIs:', err));

// Gráfica Top Productos (Bar Chart)
fetch('/api/reporte/top-productos?n=10')
    .then(r => r.json())
    .then(data => {
        if (!data || data.length === 0) {
            document.getElementById('chartTopProductos').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }

        const nombres = data.map(item => item.nombre || 'N/A');
        const cantidades = data.map(item => item.cantidad_vendida || 0);

        Highcharts.chart('chartTopProductos', {
            chart: { type: 'bar', backgroundColor: 'transparent' },
            title: { text: null },
            xAxis: { categories: nombres, title: { text: null } },
            yAxis: { title: { text: 'Unidades Vendidas' }, min: 0 },
            legend: { enabled: false },
            plotOptions: {
                bar: {
                    dataLabels: { enabled: true, format: '{y}' },
                    color: '#ff9500'
                }
            },
            series: [{
                name: 'Unidades Vendidas',
                data: cantidades
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error cargando top productos:', err);
        document.getElementById('chartTopProductos').innerHTML = '<p class="text-center text-danger">Error cargando datos</p>';
    });

// Gráfica Facturación Diaria (Line Chart) - usando VIEW vfacturaciondiaria
fetch('/api/reporte/facturacion-diaria')
    .then(r => r.json())
    .then(data => {
        if (!data || data.length === 0) {
            document.getElementById('chartFacturacion').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }

        // Obtener últimos 7 días
        const ultimos7 = data.slice(-7);
        const diasSemana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
        const fechas = ultimos7.map((item, index) => {
            if (item.fecha) {
                const fecha = new Date(item.fecha);
                return diasSemana[fecha.getDay()] || item.dia || 'N/A';
            }
            return item.dia || diasSemana[index] || 'N/A';
        });
        const totales = ultimos7.map(item => item.total_facturado || 0);
        const subtotales = ultimos7.map(item => item.subtotal || 0);
        const impuestos = ultimos7.map(item => item.impuestos || 0);

        Highcharts.chart('chartFacturacion', {
            chart: { type: 'line', backgroundColor: 'transparent' },
            title: { text: null },
            xAxis: { categories: fechas, title: { text: null } },
            yAxis: [{
                title: { text: 'Monto ($)' },
                min: 0,
                labels: { format: '${value}' }
            }, {
                title: { text: 'Número de Facturas' },
                opposite: true,
                min: 0
            }],
            legend: {
                enabled: true,
                align: 'center',
                verticalAlign: 'bottom'
            },
            tooltip: {
                shared: true,
                valuePrefix: '$',
                valueSuffix: ' facturas'
            },
            plotOptions: {
                line: {
                    marker: { enabled: true, radius: 4 }
                }
            },
            series: [{
                name: 'Total Facturado',
                yAxis: 0,
                data: totales,
                color: '#8b5cf6',
                lineWidth: 3
            }, {
                name: 'Subtotal',
                yAxis: 0,
                data: subtotales,
                color: '#3b82f6',
                lineWidth: 2
            }, {
                name: 'Impuestos',
                yAxis: 0,
                data: impuestos,
                color: '#10b981',
                lineWidth: 2
            }, {
                name: 'Número de Facturas',
                type: 'column',
                yAxis: 1,
                data: ultimos7.map(item => item.numero_facturas || 0),
                color: '#f59e0b'
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error cargando facturación:', err);
        document.getElementById('chartFacturacion').innerHTML = '<p class="text-center text-danger">Error cargando datos</p>';
    });

// Gráfica Margen por Categoría (Column Chart)
fetch('/api/reporte/margen-categoria')
    .then(r => r.json())
    .then(data => {
        if (!data || data.length === 0) {
            document.getElementById('chartMargenCategoria').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }

        const categorias = data.map(item => item.nombre_categoria || 'N/A');
        const ingresos = data.map(item => item.ingreso_total || 0);
        const margenes = data.map(item => item.margen_bruto || 0);

        Highcharts.chart('chartMargenCategoria', {
            chart: { type: 'column', backgroundColor: 'transparent' },
            title: { text: null },
            xAxis: { categories: categorias, title: { text: null } },
            yAxis: { title: { text: 'Monto ($)' }, min: 0 },
            legend: { enabled: true, align: 'center', verticalAlign: 'bottom' },
            plotOptions: {
                column: {
                    dataLabels: { enabled: true, format: '${point.y:,.0f}' }
                }
            },
            series: [
                {
                    name: 'Ingresos Totales',
                    data: ingresos,
                    color: '#3b82f6'
                },
                {
                    name: 'Margen Bruto',
                    data: margenes,
                    color: '#10b981'
                }
            ],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error cargando margen categoría:', err);
        document.getElementById('chartMargenCategoria').innerHTML = '<p class="text-center text-danger">Error cargando datos</p>';
    });
