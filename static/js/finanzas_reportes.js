// Cargar todos los reportes financieros automáticamente al cargar la página
document.addEventListener('DOMContentLoaded', function() {
    console.log('✓ Cargando reportes financieros...');
    cargarTodosLosReportes();
});

function cargarTodosLosReportes() {
    // Cargar todos los reportes de forma asíncrona
    Promise.allSettled([
        safeLoad(cargarResumenFinanciero),
        safeLoad(cargarFacturacionAnio),
        safeLoad(cargarEstadoPagos),
        safeLoad(cargarPagosMetodo),
        safeLoad(cargarTopClientes),
        safeLoad(cargarFacturacionMensual)
    ]).then(() => {
        console.log('✓ Todos los reportes financieros cargados');
    });
}

// Helper para cargar reportes de forma segura
function safeLoad(loadFunction) {
    return Promise.resolve(loadFunction()).catch(err => {
        console.error('Error en carga:', err);
        return Promise.resolve();
    });
}

// Resumen Financiero
function cargarResumenFinanciero() {
    console.log('[DEBUG] Iniciando carga de resumen financiero...');
    return fetch('/api/finanzas/reporte/resumen')
        .then(r => {
            console.log('[DEBUG] Respuesta recibida, status:', r.status);
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('✓ Datos resumen financiero recibidos:', data);
            
            const ingresosEl = document.getElementById('kpiIngresosTotales');
            const facturasEl = document.getElementById('kpiTotalFacturas');
            const pagadasEl = document.getElementById('kpiFacturasPagadas');
            const pendienteEl = document.getElementById('kpiPendienteCobrar');
            
            console.log('[DEBUG] Elementos encontrados:', {
                ingresos: !!ingresosEl,
                facturas: !!facturasEl,
                pagadas: !!pagadasEl,
                pendiente: !!pendienteEl
            });
            
            if (ingresosEl) {
                const valor = data.ingresos_totales || 0;
                ingresosEl.textContent = '$' + new Intl.NumberFormat('es-MX', {
                    minimumFractionDigits: 2, 
                    maximumFractionDigits: 2
                }).format(valor);
                console.log('[DEBUG] Ingresos actualizados:', valor);
            }
            if (facturasEl) {
                const valor = data.total_facturas || 0;
                facturasEl.textContent = new Intl.NumberFormat('es-MX').format(valor);
                console.log('[DEBUG] Facturas actualizadas:', valor);
            }
            if (pagadasEl) {
                const valor = data.facturas_pagadas || 0;
                pagadasEl.textContent = new Intl.NumberFormat('es-MX').format(valor);
                console.log('[DEBUG] Facturas pagadas actualizadas:', valor);
            }
            if (pendienteEl) {
                const valor = data.pendiente_cobrar || 0;
                pendienteEl.textContent = '$' + new Intl.NumberFormat('es-MX', {
                    minimumFractionDigits: 2, 
                    maximumFractionDigits: 2
                }).format(valor);
                console.log('[DEBUG] Pendiente actualizado:', valor);
            }
            
            // Mostrar mensaje si no hay facturas
            const mensajeSinDatos = document.getElementById('mensajeSinDatos');
            if (mensajeSinDatos && (data.total_facturas === 0 || !data.total_facturas)) {
                mensajeSinDatos.style.display = 'block';
            } else if (mensajeSinDatos) {
                mensajeSinDatos.style.display = 'none';
            }
        })
        .catch(err => {
            console.error('✗ Error cargando resumen financiero:', err);
            console.error('✗ Stack trace:', err.stack);
            const ingresosEl = document.getElementById('kpiIngresosTotales');
            const facturasEl = document.getElementById('kpiTotalFacturas');
            const pagadasEl = document.getElementById('kpiFacturasPagadas');
            const pendienteEl = document.getElementById('kpiPendienteCobrar');
            
            if (ingresosEl) ingresosEl.textContent = '$0';
            if (facturasEl) facturasEl.textContent = '0';
            if (pagadasEl) pagadasEl.textContent = '0';
            if (pendienteEl) pendienteEl.textContent = '$0';
        });
}

// Facturación por Año
function cargarFacturacionAnio() {
    return fetch('/api/finanzas/reporte/facturacion-anio')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('✓ Datos facturación por año:', data);
            
            const container = document.getElementById('chartFacturacionAnio');
            if (!container) return;
            
            if (!data || data.length === 0) {
                container.innerHTML = '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
                return;
            }
            
            const anios = data.map(d => d.anio || 'N/A');
            const totales = data.map(d => parseFloat(d.total || 0));
            
            Highcharts.chart('chartFacturacionAnio', {
                chart: { type: 'column' },
                title: { text: 'Facturación por Año (Últimos 5 Años)' },
                xAxis: { categories: anios, title: { text: 'Año' } },
                yAxis: { title: { text: 'Monto ($)' } },
                series: [{
                    name: 'Facturación',
                    data: totales,
                    color: '#11998e'
                }],
                tooltip: {
                    pointFormat: '<b>${point.y:,.2f}</b>'
                },
                credits: { enabled: false }
            });
        })
        .catch(err => {
            console.error('✗ Error cargando facturación por año:', err);
            const container = document.getElementById('chartFacturacionAnio');
            if (container) {
                container.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            }
        });
}

// Estado de Pagos
function cargarEstadoPagos() {
    return fetch('/api/finanzas/reporte/estado-pagos')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('✓ Datos estado de pagos:', data);
            
            const container = document.getElementById('chartEstadoPagos');
            if (!container) return;
            
            if (!data || data.length === 0) {
                container.innerHTML = '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
                return;
            }
            
            const seriesData = data.map(d => ({
                name: d.estado || 'N/A',
                y: parseInt(d.cantidad || 0)
            }));
            
            Highcharts.chart('chartEstadoPagos', {
                chart: { type: 'pie' },
                title: { text: 'Distribución de Facturas por Estado de Pago' },
                series: [{
                    name: 'Facturas',
                    data: seriesData,
                    dataLabels: {
                        enabled: true,
                        format: '<b>{point.name}</b>: {point.y} ({point.percentage:.1f}%)'
                    }
                }],
                tooltip: {
                    pointFormat: '{series.name}: <b>{point.y}</b><br/>Porcentaje: <b>{point.percentage:.1f}%</b>'
                },
                credits: { enabled: false }
            });
        })
        .catch(err => {
            console.error('✗ Error cargando estado de pagos:', err);
            const container = document.getElementById('chartEstadoPagos');
            if (container) {
                container.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            }
        });
}

// Pagos por Método
function cargarPagosMetodo() {
    return fetch('/api/finanzas/reporte/pagos-metodo')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('✓ Datos pagos por método:', data);
            
            const container = document.getElementById('chartPagosMetodo');
            if (!container) return;
            
            if (!data || data.length === 0) {
                container.innerHTML = '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
                return;
            }
            
            const metodos = data.map(d => d.metodo_pago || 'N/A');
            const montos = data.map(d => parseFloat(d.monto_total || 0));
            
            Highcharts.chart('chartPagosMetodo', {
                chart: { type: 'bar' },
                title: { text: 'Pagos por Método de Pago' },
                xAxis: { categories: metodos, title: { text: 'Método de Pago' } },
                yAxis: { title: { text: 'Monto ($)' } },
                series: [{
                    name: 'Monto Total',
                    data: montos,
                    color: '#4facfe'
                }],
                tooltip: {
                    pointFormat: '<b>${point.y:,.2f}</b>'
                },
                credits: { enabled: false }
            });
        })
        .catch(err => {
            console.error('✗ Error cargando pagos por método:', err);
            const container = document.getElementById('chartPagosMetodo');
            if (container) {
                container.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            }
        });
}

// Top Clientes por Facturación
function cargarTopClientes() {
    return fetch('/api/finanzas/reporte/top-clientes')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('✓ Datos top clientes:', data);
            
            const container = document.getElementById('chartTopClientes');
            if (!container) return;
            
            if (!data || data.length === 0) {
                container.innerHTML = '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
                return;
            }
            
            const clientes = data.map(d => d.nombre_cliente || 'N/A');
            const montos = data.map(d => parseFloat(d.total_facturado || 0));
            
            Highcharts.chart('chartTopClientes', {
                chart: { type: 'column' },
                title: { text: 'Top 10 Clientes por Facturación' },
                xAxis: { categories: clientes, title: { text: 'Cliente' } },
                yAxis: { title: { text: 'Monto Facturado ($)' } },
                series: [{
                    name: 'Facturación',
                    data: montos,
                    color: '#43e97b'
                }],
                tooltip: {
                    pointFormat: '<b>${point.y:,.2f}</b>'
                },
                credits: { enabled: false }
            });
        })
        .catch(err => {
            console.error('✗ Error cargando top clientes:', err);
            const container = document.getElementById('chartTopClientes');
            if (container) {
                container.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            }
        });
}

// Facturación Mensual
function cargarFacturacionMensual() {
    return fetch('/api/finanzas/reporte/facturacion-mensual')
        .then(r => {
            if (!r.ok) {
                throw new Error(`HTTP ${r.status}: ${r.statusText}`);
            }
            return r.json();
        })
        .then(data => {
            console.log('✓ Datos facturación mensual:', data);
            
            const container = document.getElementById('chartFacturacionMensual');
            if (!container) return;
            
            if (!data || data.length === 0) {
                container.innerHTML = '<p class="text-center text-muted py-4">No hay datos disponibles</p>';
                return;
            }
            
            const meses = data.map(d => d.mes || 'N/A');
            const totales = data.map(d => parseFloat(d.total || 0));
            
            Highcharts.chart('chartFacturacionMensual', {
                chart: { type: 'line' },
                title: { text: 'Facturación Mensual (Últimos 12 Meses)' },
                xAxis: { categories: meses, title: { text: 'Mes' } },
                yAxis: { title: { text: 'Monto ($)' } },
                series: [{
                    name: 'Facturación',
                    data: totales,
                    color: '#fa709a',
                    marker: { enabled: true, radius: 4 }
                }],
                tooltip: {
                    pointFormat: '<b>${point.y:,.2f}</b>'
                },
                credits: { enabled: false }
            });
        })
        .catch(err => {
            console.error('✗ Error cargando facturación mensual:', err);
            const container = document.getElementById('chartFacturacionMensual');
            if (container) {
                container.innerHTML = '<p class="text-center text-danger py-4">Error al cargar los datos</p>';
            }
        });
}

