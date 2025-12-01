// Cargar KPIs
fetch('/api/auditor/kpis')
    .then(r => r.json())
    .then(data => {
        // Registros Auditados
        document.getElementById('kpiRegistros').textContent = new Intl.NumberFormat('es-MX').format(data.registros_auditados || 0);
        const registrosTrendEl = document.getElementById('kpiRegistrosTrend');
        if (data.registros_trend !== undefined) {
            const trend = data.registros_trend || 0;
            registrosTrendEl.innerHTML = `<span>${trend >= 0 ? '+' : ''}${trend}</span>`;
            registrosTrendEl.className = `kpi-trend ${trend >= 0 ? 'positive' : 'negative'}`;
        }

        // Discrepancias
        document.getElementById('kpiDiscrepancias').textContent = new Intl.NumberFormat('es-MX').format(data.discrepancias || 0);
        const discrepanciasTrendEl = document.getElementById('kpiDiscrepanciasTrend');
        if (data.discrepancias_trend !== undefined) {
            const trend = data.discrepancias_trend || 0;
            discrepanciasTrendEl.innerHTML = `<span>${trend >= 0 ? '+' : ''}${trend}</span>`;
            discrepanciasTrendEl.className = `kpi-trend ${trend <= 0 ? 'positive' : 'negative'}`;
        }

        // Conformidad
        document.getElementById('kpiConformidad').textContent = (data.conformidad || 0).toFixed(1) + '%';
        const conformidadTrendEl = document.getElementById('kpiConformidadTrend');
        if (data.conformidad_trend !== undefined) {
            const trend = data.conformidad_trend || 0;
            conformidadTrendEl.innerHTML = `<span>${trend >= 0 ? '+' : ''}${trend.toFixed(1)}%</span>`;
            conformidadTrendEl.className = `kpi-trend ${trend >= 0 ? 'positive' : 'negative'}`;
        }

        // Reportes Generados
        document.getElementById('kpiReportes').textContent = new Intl.NumberFormat('es-MX').format(data.reportes_generados || 0);
        const reportesTrendEl = document.getElementById('kpiReportesTrend');
        if (data.reportes_trend !== undefined) {
            const trend = data.reportes_trend || 0;
            reportesTrendEl.innerHTML = `<span>${trend >= 0 ? '+' : ''}${trend}</span>`;
            reportesTrendEl.className = `kpi-trend ${trend >= 0 ? 'positive' : 'negative'}`;
        }
    })
    .catch(err => {
        console.error('Error cargando KPIs:', err);
    });

// Gráfica Devoluciones por Motivo (Pie Chart)
fetch('/api/auditor/devoluciones-motivo')
    .then(r => r.json())
    .then(data => {
        if (!data || data.length === 0) {
            document.getElementById('chartDevoluciones').innerHTML = '<p class="text-center text-muted py-5"><i class="bi bi-inbox"></i> No hay datos de devoluciones disponibles</p>';
            return;
        }

        // Filtrar datos con cantidad > 0 y ordenar por cantidad descendente
        const filteredData = data
            .filter(item => (item.cantidad || 0) > 0)
            .sort((a, b) => (b.cantidad || 0) - (a.cantidad || 0));

        if (filteredData.length === 0) {
            document.getElementById('chartDevoluciones').innerHTML = '<p class="text-center text-muted py-5"><i class="bi bi-inbox"></i> No hay devoluciones registradas</p>';
            return;
        }

        // Generar colores dinámicamente (tonos de púrpura)
        const purpleColors = [
            '#8b5cf6', '#7c3aed', '#6d28d9', '#5b21b6', '#4c1d95',
            '#a78bfa', '#8b5cf6', '#7c3aed', '#6d28d9', '#5b21b6'
        ];

        const pieData = filteredData.map((item, index) => ({
            name: item.motivo || 'N/A',
            y: item.cantidad || 0,
            color: purpleColors[index % purpleColors.length]
        }));

        Highcharts.chart('chartDevoluciones', {
            chart: {
                type: 'pie',
                backgroundColor: 'transparent',
                height: 350
            },
            title: { text: null },
            tooltip: {
                pointFormat: '<b>{point.name}</b><br/>Cantidad: <b>{point.y}</b><br/>Porcentaje: <b>{point.percentage:.1f}%</b>'
            },
            plotOptions: {
                pie: {
                    allowPointSelect: true,
                    cursor: 'pointer',
                    dataLabels: {
                        enabled: true,
                        format: '<b>{point.name}</b>: {point.y}',
                        style: {
                            fontSize: '11px',
                            fontWeight: 'normal'
                        },
                        distance: -30
                    },
                    showInLegend: true
                }
            },
            legend: {
                enabled: true,
                layout: 'vertical',
                align: 'right',
                verticalAlign: 'middle',
                itemStyle: {
                    fontSize: '11px'
                }
            },
            series: [{
                name: 'Devoluciones',
                data: pieData,
                size: '80%',
                innerSize: '0%'
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error cargando devoluciones:', err);
        document.getElementById('chartDevoluciones').innerHTML = '<p class="text-center text-danger py-5"><i class="bi bi-exclamation-triangle"></i> Error cargando datos</p>';
    });

// Gráfica Actividad de Auditoría por Módulo (Bar Chart)
fetch('/api/auditor/actividad-modulo')
    .then(r => r.json())
    .then(data => {
        if (!data) {
            document.getElementById('chartActividadModulo').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }

        const categorias = ['Inventario', 'Ventas', 'Facturas', 'Usuarios'];
        const conformes = [
            data.inventario?.conformes || 0,
            data.ventas?.conformes || 0,
            data.facturas?.conformes || 0,
            data.usuarios?.conformes || 0
        ];
        const discrepancias = [
            data.inventario?.discrepancias || 0,
            data.ventas?.discrepancias || 0,
            data.facturas?.discrepancias || 0,
            data.usuarios?.discrepancias || 0
        ];

        Highcharts.chart('chartActividadModulo', {
            chart: {
                type: 'column',
                backgroundColor: 'transparent',
                height: 300
            },
            title: { text: null },
            xAxis: {
                categories: categorias,
                title: { text: null }
            },
            yAxis: {
                title: { text: 'Cantidad' },
                min: 0
            },
            legend: {
                enabled: true,
                align: 'center',
                verticalAlign: 'bottom'
            },
            plotOptions: {
                column: {
                    dataLabels: { enabled: true },
                    stacking: 'normal'
                }
            },
            series: [{
                name: 'Conformes',
                data: conformes,
                color: '#10b981'
            }, {
                name: 'Discrepancias',
                data: discrepancias,
                color: '#ef4444'
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error cargando actividad por módulo:', err);
        document.getElementById('chartActividadModulo').innerHTML = '<p class="text-center text-danger">Error cargando datos</p>';
    });

// Cargar Registros Recientes
fetch('/api/auditor/registros-recientes')
    .then(r => r.json())
    .then(data => {
        const tbody = document.getElementById('tablaRegistrosRecientes');
        if (!data || data.length === 0) {
            tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted py-4"><i class="bi bi-inbox"></i> No hay registros disponibles</td></tr>';
            return;
        }

        tbody.innerHTML = data.map(registro => {
            const fecha = registro.fecha ? new Date(registro.fecha).toLocaleDateString('es-MX') : 'N/A';
            const estadoClass = registro.estado === 'Conforme' ? 'badge-conforme' : 'badge-discrepancia';
            return `
                <tr>
                    <td><strong>${registro.tipo}</strong></td>
                    <td>#${registro.id_registro}</td>
                    <td>${fecha}</td>
                    <td>${registro.estado_inicial || 'N/A'}</td>
                    <td>${registro.estado_final || 'N/A'}</td>
                    <td><span class="${estadoClass}">${registro.estado}</span></td>
                </tr>
            `;
        }).join('');
    })
    .catch(err => {
        console.error('Error cargando registros recientes:', err);
        document.getElementById('tablaRegistrosRecientes').innerHTML = '<tr><td colspan="6" class="text-center text-danger py-4"><i class="bi bi-exclamation-triangle"></i> Error cargando datos</td></tr>';
    });
