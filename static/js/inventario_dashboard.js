// Cargar KPIs
fetch('/api/inventario/kpis')
    .then(r => r.json())
    .then(data => {
        document.getElementById('kpiStock').textContent = new Intl.NumberFormat('es-MX').format(data.productos_stock || 0);
        document.getElementById('kpiStockBajo').textContent = new Intl.NumberFormat('es-MX').format(data.stock_bajo || 0);
        document.getElementById('kpiValor').textContent = '$' + new Intl.NumberFormat('es-MX').format(data.valor_inventario || 0);
        document.getElementById('kpiRotacion').textContent = (data.rotacion_promedio || 0).toFixed(1);
    })
    .catch(err => console.error('Error cargando KPIs:', err));

// Gráfica Estado de Stock
fetch('/api/inventario/estado-stock')
    .then(r => r.json())
    .then(data => {
        console.log('Datos recibidos para gráfica:', data);
        const normal = parseInt(data.normal) || 0;
        const bajo = parseInt(data.bajo) || 0;
        console.log('Normal:', normal, 'Bajo:', bajo);
        
        Highcharts.chart('chartEstadoStock', {
            chart: { type: 'pie', backgroundColor: 'transparent', height: 300 },
            title: { text: null },
            plotOptions: {
                pie: {
                    allowPointSelect: true,
                    cursor: 'pointer',
                    dataLabels: { 
                        enabled: true,
                        format: '{point.name}: {point.y} ({point.percentage:.1f}%)'
                    }
                }
            },
            series: [{
                name: 'Cantidad',
                data: [
                    { name: 'Normal', y: normal, color: '#10b981' },
                    { name: 'Bajo', y: bajo, color: '#f59e0b' },
                ]
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => console.error('Error cargando estado stock:', err));
