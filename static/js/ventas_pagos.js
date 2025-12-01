let modalPago;

document.addEventListener('DOMContentLoaded', function () {
    modalPago = new bootstrap.Modal(document.getElementById('modalPago'));

    // Validar importe máximo
    document.getElementById('pagoImporte').addEventListener('input', function () {
        const importe = parseFloat(this.value) || 0;
        const pendiente = parseFloat(document.getElementById('pagoPendiente').textContent.replace(/,/g, '')) || 0;

        if (importe > pendiente) {
            this.setCustomValidity('El importe no puede ser mayor al pendiente');
        } else {
            this.setCustomValidity('');
        }
    });

    // Registrar pago
    document.getElementById('btnRegistrarPago').addEventListener('click', function () {
        const form = document.getElementById('formPago');
        if (!form.checkValidity()) {
            form.reportValidity();
            return;
        }

        const data = {
            id_factura: parseInt(document.getElementById('pagoIdFactura').value),
            importe: parseFloat(document.getElementById('pagoImporte').value),
            id_metodo_pago: parseInt(document.getElementById('pagoMetodo').value)
        };

        // Deshabilitar botón
        const btn = this;
        btn.disabled = true;
        btn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Procesando...';

        fetch('/api/ventas/pagos/registrar', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    alert(data.mensaje || 'Pago registrado exitosamente');
                    modalPago.hide();
                    location.reload();
                } else {
                    alert('Error: ' + (data.mensaje || data.error || 'No se pudo registrar el pago'));
                    btn.disabled = false;
                    btn.innerHTML = '<i class="bi bi-credit-card"></i> Registrar Pago';
                }
            })
            .catch(error => {
                console.error('Error:', error);
                alert('Error al registrar el pago');
                btn.disabled = false;
                btn.innerHTML = '<i class="bi bi-credit-card"></i> Registrar Pago';
            });
    });
});

function abrirModalPago(idFactura, pendiente) {
    document.getElementById('pagoIdFactura').value = idFactura;
    document.getElementById('pagoNumFactura').textContent = idFactura;
    document.getElementById('pagoPendiente').textContent = pendiente.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    document.getElementById('pagoImporte').value = '';
    document.getElementById('pagoImporte').max = pendiente;
    document.getElementById('pagoMetodo').value = '';
    document.getElementById('formPago').reset();
    modalPago.show();
}
