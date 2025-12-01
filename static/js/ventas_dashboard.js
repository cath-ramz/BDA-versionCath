// Cargar KPIs
fetch('/api/ventas/kpis')
    .then(r => r.json())
    .then(data => {
        // Ventas Hoy
        document.getElementById('kpiVentasHoy').textContent = '$' + new Intl.NumberFormat('es-MX').format(data.ventas_hoy || 0);
        const ventasTrendEl = document.getElementById('kpiVentasTrend');
        const ventasTrend = data.ventas_trend || 0;
        ventasTrendEl.innerHTML = `<span>${ventasTrend >= 0 ? '+' : ''}${ventasTrend.toFixed(1)}%</span>`;
        ventasTrendEl.className = `kpi-trend ${ventasTrend >= 0 ? 'positive' : 'negative'}`;

        // Comisión
        document.getElementById('kpiComision').textContent = '$' + new Intl.NumberFormat('es-MX').format(data.comision_acumulada || 0);
        const comisionTrendEl = document.getElementById('kpiComisionTrend');
        const comisionTrend = data.comision_trend || 0;
        comisionTrendEl.innerHTML = `<span>${comisionTrend >= 0 ? '+' : ''}${comisionTrend.toFixed(1)}%</span>`;
        comisionTrendEl.className = `kpi-trend ${comisionTrend >= 0 ? 'positive' : 'negative'}`;

        // Clientes
        document.getElementById('kpiClientes').textContent = new Intl.NumberFormat('es-MX').format(data.clientes_atendidos || 0);
        const clientesTrendEl = document.getElementById('kpiClientesTrend');
        const clientesTrend = data.clientes_trend || 0;
        clientesTrendEl.innerHTML = `<span>${clientesTrend >= 0 ? '+' : ''}${clientesTrend}</span>`;
        clientesTrendEl.className = `kpi-trend ${clientesTrend >= 0 ? 'positive' : 'negative'}`;

        // Pedidos
        document.getElementById('kpiPedidos').textContent = new Intl.NumberFormat('es-MX').format(data.pedidos_pendientes || 0);
        const pedidosTrendEl = document.getElementById('kpiPedidosTrend');
        const pedidosTrend = data.pedidos_trend || 0;
        pedidosTrendEl.innerHTML = `<span>${pedidosTrend >= 0 ? '+' : ''}${pedidosTrend}</span>`;
        pedidosTrendEl.className = `kpi-trend ${pedidosTrend >= 0 ? 'positive' : 'negative'}`;
    })
    .catch(err => {
        console.error('Error cargando KPIs:', err);
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
            chart: {
                type: 'bar',
                backgroundColor: 'transparent',
                height: 300
            },
            title: { text: null },
            xAxis: {
                categories: data.map(p => p.nombre),
                title: { text: null }
            },
            yAxis: {
                title: { text: 'Unidades Vendidas' },
                min: 0
            },
            plotOptions: {
                bar: {
                    dataLabels: { enabled: true }
                }
            },
            series: [{
                name: 'Unidades Vendidas',
                data: data.map(p => p.unidades_vendidas),
                color: '#3b82f6'
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error cargando top productos:', err);
        document.getElementById('chartTopProductos').innerHTML = '<p class="text-center text-danger">Error cargando datos</p>';
    });

// Gráfica Ventas Semanales
fetch('/api/ventas/ventas-semanal')
    .then(r => r.json())
    .then(data => {
        if (!data) {
            document.getElementById('chartVentasSemanal').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }

        Highcharts.chart('chartVentasSemanal', {
            chart: {
                type: 'line',
                backgroundColor: 'transparent',
                height: 300
            },
            title: { text: null },
            xAxis: {
                categories: data.dias || [],
                title: { text: null }
            },
            yAxis: {
                title: { text: 'Ventas ($)' },
                min: 0
            },
            plotOptions: {
                line: {
                    dataLabels: { enabled: true },
                    enableMouseTracking: true
                }
            },
            series: [{
                name: 'Ventas',
                data: data.ventas || [],
                color: '#10b981'
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error cargando ventas semanales:', err);
        document.getElementById('chartVentasSemanal').innerHTML = '<p class="text-center text-danger">Error cargando datos</p>';
    });

// Ticket Promedio - KPI Cards y Gráfica (usando VIEW vticketspromedio)
fetch('/api/reporte/ticket-promedio')
    .then(r => r.json())
    .then(data => {
        if (!data || data.error) {
            document.getElementById('chartTicketPromedio').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }

        const ticketPromedio = data.ticket_promedio || 0;
        const numeroPedidos = data.numero_total_pedidos || 0;
        const ingresosTotales = data.ingresos_totales || 0;

        // Actualizar KPI Cards
        document.getElementById('kpiTicketPromedio').textContent = '$' + new Intl.NumberFormat('es-MX', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(ticketPromedio);
        document.getElementById('kpiTotalPedidos').textContent = new Intl.NumberFormat('es-MX').format(numeroPedidos);
        document.getElementById('kpiIngresosTotales').textContent = '$' + new Intl.NumberFormat('es-MX', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(ingresosTotales);

        // Gráfica de barras comparativa más visual
        Highcharts.chart('chartTicketPromedio', {
            chart: {
                type: 'bar',
                backgroundColor: 'transparent',
                height: 300
            },
            title: { text: null },
            xAxis: {
                categories: ['Ticket Promedio', 'Ingresos Totales'],
                title: { text: null }
            },
            yAxis: {
                title: { text: 'Monto ($)' },
                min: 0,
                labels: { format: '${value}' }
            },
            legend: { enabled: false },
            tooltip: {
                valuePrefix: '$',
                valueDecimals: 2
            },
            plotOptions: {
                bar: {
                    dataLabels: {
                        enabled: true,
                        format: '${value:,.2f}',
                        style: {
                            fontWeight: 'bold',
                            fontSize: '12px'
                        }
                    },
                    colorByPoint: true,
                    colors: ['#8b5cf6', '#3b82f6']
                }
            },
            series: [{
                name: 'Valor',
                data: [ticketPromedio, ingresosTotales]
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error cargando ticket promedio:', err);
        document.getElementById('chartTicketPromedio').innerHTML = '<p class="text-center text-danger">Error cargando datos</p>';
    });

// Progreso de Metas Mensuales
fetch('/api/ventas/kpis')
    .then(r => r.json())
    .then(data => {
        const container = document.getElementById('progresoMetas');
        const ventasMes = data.ventas_mes || 0;
        const pedidosCompletados = data.pedidos_completados || 0;
        const metaMensual = 50000; // Meta fija de ventas
        const progreso = Math.min((ventasMes / metaMensual) * 100, 100);

        container.innerHTML = `
            <div class="p-3">
                <div class="mb-4">
                    <div class="d-flex justify-content-between mb-2">
                        <span class="fw-semibold">Meta de Ventas</span>
                        <span class="text-muted">$${new Intl.NumberFormat('es-MX').format(ventasMes)} / $${new Intl.NumberFormat('es-MX').format(metaMensual)}</span>
                    </div>
                    <div class="progress" style="height: 20px;">
                        <div class="progress-bar bg-success" role="progressbar" style="width: ${progreso}%">
                            ${progreso.toFixed(1)}%
                        </div>
                    </div>
                </div>
                <div class="mb-4">
                    <div class="d-flex justify-content-between mb-2">
                        <span class="fw-semibold">Clientes Recurrentes</span>
                        <span class="text-muted">${data.clientes_atendidos || 0} / 100</span>
                    </div>
                    <div class="progress" style="height: 20px;">
                        <div class="progress-bar bg-info" role="progressbar" style="width: ${Math.min((data.clientes_atendidos || 0), 100)}%">
                            ${data.clientes_atendidos || 0}%
                        </div>
                    </div>
                </div>
                <div class="mb-4">
                    <div class="d-flex justify-content-between mb-2">
                        <span class="fw-semibold">Pedidos Completados</span>
                        <span class="text-muted">${pedidosCompletados} / 50</span>
                    </div>
                    <div class="progress" style="height: 20px;">
                        <div class="progress-bar bg-primary" role="progressbar" style="width: ${Math.min((pedidosCompletados / 50) * 100, 100)}%">
                            ${(pedidosCompletados / 50 * 100).toFixed(1)}%
                        </div>
                    </div>
                </div>
            </div>
        `;
    })
    .catch(err => {
        console.error('Error cargando metas:', err);
        document.getElementById('progresoMetas').innerHTML = '<p class="text-center text-muted">No hay datos de metas disponibles</p>';
    });

// Pedidos Pendientes de Seguimiento
fetch('/api/ventas/kpis')
    .then(r => r.json())
    .then(data => {
        const container = document.getElementById('pedidosPendientes');
        const pendientes = data.pedidos_pendientes || 0;

        if (pendientes === 0) {
            container.innerHTML = `
                <div class="text-center p-4">
                    <i class="bi bi-check-circle text-success" style="font-size: 3rem;"></i>
                    <h5 class="mt-3 text-success">¡Excelente!</h5>
                    <p class="text-muted">No hay pedidos pendientes de seguimiento</p>
                </div>
            `;
        } else {
            container.innerHTML = `
                <div class="text-center p-4">
                    <i class="bi bi-hourglass-split text-warning" style="font-size: 3rem;"></i>
                    <h5 class="mt-3">${pendientes} Pedidos Pendientes</h5>
                    <p class="text-muted">Requieren atención</p>
                    <a href="/ventas/pedidos" class="btn btn-outline-primary mt-2">
                        <i class="bi bi-eye"></i> Ver Pedidos
                    </a>
                </div>
            `;
        }
    })
    .catch(err => {
        console.error('Error cargando pedidos pendientes:', err);
        document.getElementById('pedidosPendientes').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
    });
