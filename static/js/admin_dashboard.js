// Cargar KPIs
fetch('/api/reporte/kpis')
    .then(r => {
        if (!r.ok) {
            throw new Error(`HTTP ${r.status}: ${r.statusText}`);
        }
        return r.json();
    })
    .then(data => {
        console.log('Datos KPIs recibidos:', data);

        // Ingresos Totales
        const ingresos = data.total_ventas || 0;
        const kpiIngresos = document.getElementById('kpiIngresos');
        if (kpiIngresos) {
            kpiIngresos.textContent = '$' + new Intl.NumberFormat('es-MX', {
                notation: 'compact',
                maximumFractionDigits: 1
            }).format(ingresos);
        }

        // Usuarios Activos (usando total_clientes como proxy)
        const usuarios = data.total_clientes || 0;
        const kpiUsuarios = document.getElementById('kpiUsuarios');
        if (kpiUsuarios) {
            kpiUsuarios.textContent = new Intl.NumberFormat('es-MX').format(usuarios);
        }

        // Órdenes Procesadas
        const ordenes = data.total_pedidos || 0;
        const kpiOrdenes = document.getElementById('kpiOrdenes');
        if (kpiOrdenes) {
            kpiOrdenes.textContent = new Intl.NumberFormat('es-MX').format(ordenes);
        }

        // Variedad de Catálogo (Modelos Únicos)
        const modelosUnicos = data.total_modelos_unicos || data.total_productos || 0;
        const kpiModelosUnicos = document.getElementById('kpiModelosUnicos');
        if (kpiModelosUnicos) {
            kpiModelosUnicos.textContent = new Intl.NumberFormat('es-MX').format(modelosUnicos);
        }

        // Volumen en Almacén (Piezas Físicas)
        const piezasFisicas = data.total_piezas_fisicas || 0;
        const kpiPiezasFisicas = document.getElementById('kpiPiezasFisicas');
        if (kpiPiezasFisicas) {
            kpiPiezasFisicas.textContent = new Intl.NumberFormat('es-MX').format(piezasFisicas);
        }

        // Valor del Inventario
        const valorInventario = data.valor_total_inventario || 0;
        const kpiValorInventario = document.getElementById('kpiValorInventario');
        if (kpiValorInventario) {
            kpiValorInventario.textContent = '$' + new Intl.NumberFormat('es-MX', {
                minimumFractionDigits: 2,
                maximumFractionDigits: 2
            }).format(valorInventario);
        }
    })
    .catch(err => {
        console.error('Error cargando KPIs:', err);
        // Mostrar error en los KPIs si falla la carga
        const kpiElements = ['kpiIngresos', 'kpiUsuarios', 'kpiOrdenes', 'kpiModelosUnicos', 'kpiPiezasFisicas', 'kpiValorInventario'];
        kpiElements.forEach(id => {
            const element = document.getElementById(id);
            if (element) {
                element.textContent = 'Error';
            }
        });
    });

// Gráfica Ventas por Categoría (Bar Chart)
fetch('/api/reporte/margen-categoria')
    .then(r => r.json())
    .then(data => {
        if (!data || data.length === 0) {
            document.getElementById('chartVentasCategoria').innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
            return;
        }

        const categorias = data.map(item => item.nombre_categoria || 'N/A');
        const ventas = data.map(item => item.ingreso_total || 0);

        Highcharts.chart('chartVentasCategoria', {
            chart: { type: 'column', backgroundColor: 'transparent' },
            title: { text: null },
            xAxis: { categories: categorias, title: { text: null } },
            yAxis: { title: { text: 'Ventas ($)' }, min: 0 },
            legend: { enabled: true },
            plotOptions: {
                column: {
                    dataLabels: { enabled: true, format: '${point.y:,.0f}' }
                }
            },
            series: [{
                name: 'Ventas ($)',
                data: ventas,
                color: '#3b82f6'
            }],
            credits: { enabled: false }
        });
    })
    .catch(err => {
        console.error('Error cargando ventas por categoría:', err);
        document.getElementById('chartVentasCategoria').innerHTML = '<p class="text-center text-danger">Error cargando datos</p>';
    });

// Gráfica Facturación Diaria (Line Chart)
fetch('/api/reporte/facturacion-diaria')
    .then(r => {
        if (!r.ok) {
            return r.json().then(err => {
                console.error('Error HTTP:', err);
                throw new Error(err.message || 'Error al cargar datos');
            });
        }
        return r.json();
    })
    .then(data => {
        if (!data || data.length === 0 || (data.error)) {
            const msg = data.error ? `Error: ${data.error}` : 'No hay datos disponibles';
            document.getElementById('chartFacturacion').innerHTML = `<p class="text-center text-muted">${msg}</p>`;
            return;
        }

        // Obtener últimos 7 días y formatear días de la semana
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

// Top 5 Productos Más Vendidos
// ==================== TOP PRODUCTOS CON FILTRO DE FECHAS ====================

function setDefaultTopFechas() {
    const hoy = new Date();
    const hasta = hoy.toISOString().slice(0, 10); // YYYY-MM-DD

    const desdeDate = new Date(hoy);
    desdeDate.setDate(desdeDate.getDate() - 30); // último mes
    const desde = desdeDate.toISOString().slice(0, 10);

    const inputDesde = document.getElementById('topDesde');
    const inputHasta = document.getElementById('topHasta');
    const selectN = document.getElementById('topN');

    if (inputDesde) inputDesde.value = desde;
    if (inputHasta) inputHasta.value = hasta;
    if (selectN) selectN.value = '5';
}

function cargarTopProductos() {
    const desde = document.getElementById('topDesde')?.value;
    const hasta = document.getElementById('topHasta')?.value;
    const n = document.getElementById('topN')?.value || 5;

    const params = new URLSearchParams();
    params.append('n', n);
    if (desde) params.append('desde', desde);
    if (hasta) params.append('hasta', hasta);

    const container = document.getElementById('topProductosList');
    if (container) {
        container.innerHTML = '<p class="text-center text-muted">Cargando...</p>';
    }

    fetch('/api/reporte/top-productos?' + params.toString())
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}`);
            }
            return r.json();
        })
        .then(data => {
            if (!container) return;

            if (!data || !Array.isArray(data) || data.length === 0 || data.error) {
                container.innerHTML = '<p class="text-center text-muted">No hay datos disponibles</p>';
                return;
            }

            // Calcular máximo para barras de progreso
            const maxCantidad = Math.max(...data.map(p => p.cantidad_vendida || p.Cantidad_Vendida || 0));

            // Agregar clase two-columns solo para top 10
            const containerClass = parseInt(n) === 10 ? 'top-productos-container two-columns' : 'top-productos-container';
            let html = `<div class="${containerClass}">`;
            data.forEach((producto, index) => {
                const nombre = producto.nombre || producto.Nombre || 'N/A';
                const cantidad = producto.cantidad_vendida || producto.Cantidad_Vendida || 0;
                const porcentaje = maxCantidad > 0 ? (cantidad / maxCantidad) * 100 : 0;

                // Medallas para top 3
                let medallaHTML = '';
                if (index === 0) {
                    medallaHTML = '<span class="medalla oro">🥇</span>';
                } else if (index === 1) {
                    medallaHTML = '<span class="medalla plata">🥈</span>';
                } else if (index === 2) {
                    medallaHTML = '<span class="medalla bronce">🥉</span>';
                } else {
                    medallaHTML = `<span class="medalla numero">${index + 1}</span>`;
                }

                // Colores de barra según posición
                const colores = ['#fbbf24', '#94a3b8', '#cd7f32', '#3b82f6', '#8b5cf6'];
                const colorBarra = colores[index] || '#64748b';

                html += `
                    <div class="top-producto-item">
                        <div class="top-producto-header">
                            ${medallaHTML}
                            <div class="top-producto-info">
                                <span class="top-producto-nombre">${nombre}</span>
                                <span class="top-producto-cantidad">${cantidad} unidades vendidas</span>
                            </div>
                        </div>
                        <div class="top-producto-barra-container">
                            <div class="top-producto-barra" style="width: ${porcentaje}%; background: ${colorBarra};"></div>
                        </div>
                    </div>
                `;
            });
            html += '</div>';
            container.innerHTML = html;
        })
        .catch(err => {
            console.error('Error cargando top productos:', err);
            if (container) {
                container.innerHTML = '<p class="text-center text-danger">Error cargando datos</p>';
            }
        });
}

// Inicializar filtros y cargar top al entrar al dashboard
document.addEventListener('DOMContentLoaded', () => {
    setDefaultTopFechas();
    cargarTopProductos();
});
