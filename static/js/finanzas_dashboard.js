// Cargar KPIs
fetch('/api/finanzas/kpis')
    .then(r => r.json())
    .then(data => {
        // Ingresos del Mes
        const ingresos = data.ingresos_mes || 0;
        const ingresosTrend = data.ingresos_trend || 0;
        document.getElementById('kpiIngresos').textContent = '$' + new Intl.NumberFormat('es-MX').format(ingresos);
        const ingresosTrendEl = document.getElementById('kpiIngresosTrend');
        ingresosTrendEl.innerHTML = `<i class="bi bi-arrow-up"></i><span>${ingresosTrend >= 0 ? '+' : ''}${ingresosTrend.toFixed(1)}%</span>`;
        ingresosTrendEl.className = 'kpi-trend ' + (ingresosTrend >= 0 ? 'positive' : 'negative');

        // Margen Promedio
        const margen = data.margen_promedio || 0;
        const margenTrend = data.margen_trend || 0;
        document.getElementById('kpiMargen').textContent = margen.toFixed(1) + '%';
        const margenTrendEl = document.getElementById('kpiMargenTrend');
        margenTrendEl.innerHTML = `<i class="bi bi-arrow-up"></i><span>${margenTrend >= 0 ? '+' : ''}${margenTrend.toFixed(1)}%</span>`;
        margenTrendEl.className = 'kpi-trend ' + (margenTrend >= 0 ? 'positive' : 'negative');

        // Pagos Pendientes
        const pagos = data.pagos_pendientes || 0;
        const pagosTrend = data.pagos_trend || 0;
        document.getElementById('kpiPagos').textContent = '$' + new Intl.NumberFormat('es-MX').format(pagos);
        const pagosTrendEl = document.getElementById('kpiPagosTrend');
        if (pagosTrend < 0) {
            pagosTrendEl.innerHTML = `<i class="bi bi-arrow-down"></i><span>$${Math.abs(pagosTrend).toLocaleString('es-MX')}</span>`;
            pagosTrendEl.className = 'kpi-trend positive';
        } else {
            pagosTrendEl.innerHTML = `<i class="bi bi-arrow-up"></i><span>+$${pagosTrend.toLocaleString('es-MX')}</span>`;
            pagosTrendEl.className = 'kpi-trend negative';
        }

        // Gastos Operacionales
        const gastos = data.gastos_operacionales || 0;
        const gastosTrend = data.gastos_trend || 0;
        document.getElementById('kpiGastos').textContent = '$' + new Intl.NumberFormat('es-MX').format(gastos);
        const gastosTrendEl = document.getElementById('kpiGastosTrend');
        gastosTrendEl.innerHTML = `<i class="bi bi-arrow-up"></i><span>${gastosTrend >= 0 ? '+' : ''}${gastosTrend.toFixed(1)}%</span>`;
        gastosTrendEl.className = 'kpi-trend ' + (gastosTrend >= 0 ? 'positive' : 'negative');
    })
    .catch(err => console.error('Error cargando KPIs:', err));

// Gráfica Margen por Categoría (Barras con dos series: Ventas y Margen)
fetch('/api/finanzas/margen-categoria')
    .then(r => r.json())
    .then(data => {
        if (!data || data.length === 0) {
            document.getElementById('chartMargenCategoria').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }

        Highcharts.chart('chartMargenCategoria', {
            chart: {
                type: 'column',
                backgroundColor: 'transparent',
                height: 300
            },
            title: { text: null },
            xAxis: {
                categories: data.map(c => c.categoria),
                title: { text: null }
            },
            yAxis: [{
                title: { text: null },
                min: 0,
                labels: {
                    format: '${value}'
                }
            }, {
                title: { text: null },
                min: 0,
                opposite: true,
                labels: {
                    format: '{value}%'
                }
            }],
            legend: {
                enabled: true,
                align: 'center',
                verticalAlign: 'bottom'
            },
            plotOptions: {
                column: {
                    dataLabels: { enabled: false },
                    grouping: false
                }
            },
            tooltip: {
                shared: true
            },
            series: [{
                name: 'Ventas ($)',
                type: 'column',
                yAxis: 0,
                data: data.map(c => c.ventas),
                color: '#3b82f6'
            }, {
                name: 'Margen (%)',
                type: 'column',
                yAxis: 1,
                data: data.map(c => c.margen_porcentaje),
                color: '#10b981'
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => console.error('Error cargando margen:', err));

// Gráfica Facturación vs Cobrado (Líneas)
fetch('/api/finanzas/facturacion-vs-cobrado')
    .then(r => r.json())
    .then(data => {
        if (!data || !data.meses || data.meses.length === 0) {
            document.getElementById('chartFacturacionCobrado').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }

        Highcharts.chart('chartFacturacionCobrado', {
            chart: {
                type: 'line',
                backgroundColor: 'transparent',
                height: 300
            },
            title: { text: null },
            xAxis: {
                categories: data.meses || [],
                title: { text: null }
            },
            yAxis: {
                title: { text: 'Monto ($)' },
                min: 0,
                labels: {
                    format: '${value}'
                }
            },
            legend: {
                enabled: true,
                align: 'center',
                verticalAlign: 'bottom'
            },
            plotOptions: {
                line: {
                    dataLabels: { enabled: false },
                    marker: { enabled: true, radius: 4 }
                }
            },
            tooltip: {
                shared: true,
                valuePrefix: '$'
            },
            series: [{
                name: 'Facturado ($)',
                data: data.facturado || [],
                color: '#8b5cf6'
            }, {
                name: 'Cobrado ($)',
                data: data.cobrado || [],
                color: '#10b981'
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => console.error('Error cargando facturación:', err));
