function abrirModalCancelar(idPedido) {
    document.getElementById('cancelarIdPedido').value = idPedido;
    document.getElementById('cancelarIdPedidoDisplay').value = 'Pedido #' + idPedido;
    document.getElementById('cancelarMotivo').value = '';
    document.getElementById('alertCancelarContainer').innerHTML = '';

    const modal = new bootstrap.Modal(document.getElementById('modalCancelarPedido'));
    modal.show();
}

// Esperar a que el DOM esté cargado
document.addEventListener('DOMContentLoaded', function() {
    const btnConfirmarCancelar = document.getElementById('btnConfirmarCancelar');
    
    if (!btnConfirmarCancelar) {
        console.warn('No se encontró el botón btnConfirmarCancelar');
        return;
    }
    
    btnConfirmarCancelar.addEventListener('click', function () {
        const form = document.getElementById('formCancelarPedido');

        if (!form) {
            console.error('No se encontró el formulario formCancelarPedido');
            return;
        }

        if (!form.checkValidity()) {
            form.reportValidity();
            return;
        }

        const data = {
            id_pedido: parseInt(document.getElementById('cancelarIdPedido').value),
            motivo_cancelacion: document.getElementById('cancelarMotivo').value.trim()
        };

        // Validación adicional
        if (!data.motivo_cancelacion) {
            showCancelarAlert('Por favor ingrese el motivo de cancelación', 'danger');
            return;
        }

        if (data.motivo_cancelacion.length > 200) {
            showCancelarAlert('El motivo no puede tener más de 200 caracteres', 'danger');
            return;
        }

        // Confirmar cancelación
        if (!confirm('¿Está seguro de que desea cancelar este pedido? El stock será devuelto automáticamente.')) {
            return;
        }

        // Deshabilitar botón
        const btnConfirmar = document.getElementById('btnConfirmarCancelar');
        const btnOriginalHTML = btnConfirmar.innerHTML;
        btnConfirmar.disabled = true;
        btnConfirmar.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Procesando...';

        // Enviar a la API
        fetch('/api/ventas/pedidos/cancelar', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        })
            .then(response => {
                // Verificar si la respuesta es OK
                if (!response.ok) {
                    throw new Error(`Error HTTP: ${response.status}`);
                }
                
                // Intentar parsear JSON
                return response.json().catch(err => {
                    throw new Error('Error al procesar la respuesta del servidor');
                });
            })
            .then(result => {
                // Restablecer botón
                btnConfirmar.disabled = false;
                btnConfirmar.innerHTML = btnOriginalHTML;
                
                if (result.success) {
                    showCancelarAlert(result.mensaje || 'Pedido cancelado exitosamente', 'success');
                    setTimeout(() => {
                        window.location.reload();
                    }, 1500);
                } else {
                    const errorMsg = result.mensaje || result.error || 'Error al cancelar el pedido';
                    showCancelarAlert(errorMsg, 'danger');
                }
            })
            .catch(err => {
                console.error('Error:', err);
                
                // Restablecer botón en caso de error
                btnConfirmar.disabled = false;
                btnConfirmar.innerHTML = btnOriginalHTML;
                
                showCancelarAlert('Error al cancelar el pedido: ' + err.message, 'danger');
            });
    });
});

function showCancelarAlert(message, type) {
    const alertContainer = document.getElementById('alertCancelarContainer');
    alertContainer.innerHTML = `
        <div class="alert alert-${type} alert-dismissible fade show" role="alert">
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    `;
}

// Funciones para el modal de cambiar estado
function abrirModalCambiarEstado(idPedido, estadoActual) {
    document.getElementById('cambiarEstadoIdPedido').value = idPedido;
    document.getElementById('cambiarEstadoIdPedidoDisplay').value = 'Pedido #' + idPedido;
    document.getElementById('cambiarEstadoActual').value = estadoActual || 'N/A';
    document.getElementById('cambiarEstadoNuevo').value = '';
    document.getElementById('alertCambiarEstadoContainer').innerHTML = '';

    // Mostrar badge del estado actual
    const badgeContainer = document.getElementById('cambiarEstadoActualBadge');
    const estado = estadoActual || 'N/A';
    let badgeClass = 'bg-secondary';
    let badgeText = estado;

    if (estado === 'Cancelado') {
        badgeClass = 'bg-danger';
    } else if (estado === 'Completado') {
        badgeClass = 'bg-success';
    } else if (estado === 'Procesado') {
        badgeClass = 'bg-info';
    } else if (estado === 'Confirmado') {
        badgeClass = 'bg-warning';
    }

    badgeContainer.innerHTML = `<span class="badge ${badgeClass} fs-6 px-3 py-2">${badgeText}</span>`;

    // Mostrar/ocultar info del flujo
    const infoFlujo = document.getElementById('infoFlujoEstados');
    if (estado === 'Completado' || estado === 'Cancelado') {
        infoFlujo.style.display = 'block';
        infoFlujo.className = 'alert alert-warning';
        infoFlujo.innerHTML = `
            <i class="bi bi-exclamation-triangle"></i>
            <strong>Estado Final:</strong> Este pedido está en estado "${estado}" y no se puede cambiar a otro estado.
        `;
    } else {
        infoFlujo.style.display = 'block';
        infoFlujo.className = 'alert alert-info';
    }

    // Cargar estados disponibles según el estado actual
    const selectEstado = document.getElementById('cambiarEstadoNuevo');
    const mensajeEstados = document.getElementById('mensajeEstadosDisponibles');
    selectEstado.innerHTML = '<option value="">Cargando...</option>';
    selectEstado.disabled = true;
    mensajeEstados.textContent = 'Cargando estados disponibles...';

    // Obtener estados disponibles del backend
    fetch(`/api/ventas/pedidos/${idPedido}/estados-disponibles`)
        .then(r => r.json())
        .then(result => {
            selectEstado.innerHTML = '<option value="">Seleccione un estado...</option>';

            if (result.estados_disponibles && result.estados_disponibles.length > 0) {
                result.estados_disponibles.forEach(estado => {
                    const option = document.createElement('option');
                    option.value = estado.estado_pedido;
                    option.textContent = estado.estado_pedido;
                    selectEstado.appendChild(option);
                });
                selectEstado.disabled = false;

                // Mensaje explicativo según el estado actual
                if (result.estado_actual === 'Confirmado') {
                    mensajeEstados.textContent = 'Desde "Confirmado" solo se puede cambiar a "Procesado"';
                } else if (result.estado_actual === 'Procesado') {
                    mensajeEstados.textContent = 'Desde "Procesado" se puede cambiar a "Completado" o "Cancelado"';
                } else {
                    mensajeEstados.textContent = 'Estados disponibles según el flujo permitido';
                }
            } else {
                selectEstado.innerHTML = '<option value="">No hay estados disponibles (estado final)</option>';
                selectEstado.disabled = true;
                mensajeEstados.textContent = 'Este pedido está en un estado final y no se puede cambiar';
            }
        })
        .catch(err => {
            console.error('Error cargando estados:', err);
            selectEstado.innerHTML = '<option value="">Error al cargar estados</option>';
            mensajeEstados.textContent = 'Error al cargar los estados disponibles';
            showCambiarEstadoAlert('Error al cargar los estados disponibles. Por favor, intenta de nuevo.', 'danger');
        });

    const modal = new bootstrap.Modal(document.getElementById('modalCambiarEstado'));
    modal.show();
}

// Esperar a que el DOM esté cargado para agregar el event listener
document.addEventListener('DOMContentLoaded', function() {
    const btnConfirmarCambiarEstado = document.getElementById('btnConfirmarCambiarEstado');
    
    if (!btnConfirmarCambiarEstado) {
        console.warn('No se encontró el botón btnConfirmarCambiarEstado');
        return;
    }
    
    btnConfirmarCambiarEstado.addEventListener('click', function () {
        const form = document.getElementById('formCambiarEstado');

        if (!form) {
            console.error('No se encontró el formulario formCambiarEstado');
            return;
        }

        if (!form.checkValidity()) {
            form.reportValidity();
            return;
        }

        const data = {
            id_pedido: parseInt(document.getElementById('cambiarEstadoIdPedido').value),
            estado_pedido: document.getElementById('cambiarEstadoNuevo').value.trim()
        };

        // Validación adicional
        if (!data.estado_pedido) {
            showCambiarEstadoAlert('Por favor seleccione un nuevo estado', 'danger');
            return;
        }

        const estadoActual = document.getElementById('cambiarEstadoActual').value;
        if (data.estado_pedido === estadoActual) {
            showCambiarEstadoAlert('El nuevo estado debe ser diferente al estado actual', 'warning');
            return;
        }

        // Deshabilitar botón
        const btnConfirmar = document.getElementById('btnConfirmarCambiarEstado');
        const btnOriginalHTML = btnConfirmar.innerHTML;
        btnConfirmar.disabled = true;
        btnConfirmar.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Procesando...';

        // Enviar a la API
        fetch('/api/ventas/pedidos/actualizar-estado', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        })
            .then(response => {
                // Verificar si la respuesta es OK
                if (!response.ok) {
                    throw new Error(`Error HTTP: ${response.status}`);
                }
                
                // Intentar parsear JSON
                return response.json().catch(err => {
                    throw new Error('Error al procesar la respuesta del servidor');
                });
            })
            .then(result => {
                // Restablecer botón
                btnConfirmar.disabled = false;
                btnConfirmar.innerHTML = btnOriginalHTML;
                
                if (result.success) {
                    showCambiarEstadoAlert(result.mensaje || 'Estado actualizado exitosamente', 'success');
                    setTimeout(() => {
                        window.location.reload();
                    }, 1500);
                } else {
                    const errorMsg = result.mensaje || result.error || 'Error al actualizar el estado del pedido';
                    showCambiarEstadoAlert(errorMsg, 'danger');
                }
            })
            .catch(err => {
                console.error('Error:', err);
                
                // Restablecer botón en caso de error
                btnConfirmar.disabled = false;
                btnConfirmar.innerHTML = btnOriginalHTML;
                
                showCambiarEstadoAlert('Error al actualizar el estado del pedido: ' + err.message, 'danger');
            });
    });
});

function showCambiarEstadoAlert(message, type) {
    const alertContainer = document.getElementById('alertCambiarEstadoContainer');
    alertContainer.innerHTML = `
        <div class="alert alert-${type} alert-dismissible fade show" role="alert">
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    `;
}
