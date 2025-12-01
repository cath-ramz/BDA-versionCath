// Carrito en memoria
const carrito = [];

// Click en tarjeta de producto (seleccionar / deseleccionar)
document.querySelectorAll('.producto-card').forEach(card => {
    card.addEventListener('click', function (e) {
        // Si el click fue en los botones de cantidad, no togglear selección
        if (e.target.closest('.qty-wrapper') || e.target.classList.contains('btn-qty')) {
            return;
        }

        const idProducto = parseInt(this.dataset.id);
        const precio = parseFloat(this.dataset.precio);
        const nombre = this.querySelector('h6').textContent;
        const qtyWrapper = this.querySelector('.qty-wrapper');
        const qtyInput = this.querySelector('.cantidad-producto');

        if (this.classList.contains('selected')) {
            // Remover del carrito
            this.classList.remove('selected');
            qtyWrapper.style.display = 'none';
            qtyInput.value = '1';

            const index = carrito.findIndex(item => item.id_producto === idProducto);
            if (index > -1) carrito.splice(index, 1);
        } else {
            // Agregar al carrito
            this.classList.add('selected');
            qtyWrapper.style.display = 'block';
            qtyInput.value = '1';

            const existente = carrito.find(item => item.id_producto === idProducto);
            if (existente) {
                existente.cantidad = 1;
                existente.precio = precio;
                existente.nombre = nombre;
            } else {
                carrito.push({
                    id_producto: idProducto,
                    nombre: nombre,
                    precio: precio,
                    cantidad: 1
                });
            }
        }

        actualizarCarrito();
    });
});

// Botones + / - (event delegation)
document.addEventListener('click', function (e) {
    if (!e.target.classList.contains('btn-qty')) return;

    e.stopPropagation();  // para que no se dispare el click de la card

    const action = e.target.getAttribute('data-action');
    const card = e.target.closest('.producto-card');
    const idProducto = parseInt(card.dataset.id);
    const qtyInput = card.querySelector('.cantidad-producto');

    let value = parseInt(qtyInput.value || '1', 10);
    if (action === 'plus') value++;
    if (action === 'minus') value = Math.max(1, value - 1);
    qtyInput.value = value;

    const item = carrito.find(i => i.id_producto === idProducto);
    if (item) {
        item.cantidad = value;
    }

    actualizarCarrito();
});

function actualizarCarrito() {
    const container = document.getElementById('carritoItems');
    const list = document.getElementById('carritoList');

    if (carrito.length === 0) {
        container.style.display = 'none';
        list.innerHTML = '';
        return;
    }

    container.style.display = 'block';
    list.innerHTML = carrito.map(item => `
        <div class="carrito-item">
            <div>
                <strong>${item.nombre}</strong><br>
                <small class="text-muted">
                    Cantidad: ${item.cantidad} x $${item.precio.toFixed(2)}
                </small>
            </div>
            <div>
                <strong>$${(item.precio * item.cantidad).toFixed(2)}</strong>
            </div>
        </div>
    `).join('');
}

// Crear pedido
document.getElementById('btnCrearPedido').addEventListener('click', function () {
    if (carrito.length === 0) {
        alert('Debe seleccionar al menos un producto');
        return;
    }

    // Si existe el select de cliente (Admin/Vendedor), obligar a elegir uno
    let idCliente = null;
    const clienteSelect = document.getElementById('clienteSelect');
    if (clienteSelect) {
        idCliente = clienteSelect.value;
        if (!idCliente) {
            alert('Debe seleccionar un cliente para el pedido');
            return;
        }
        idCliente = parseInt(idCliente);
    }

    const items = carrito.map(item => ({
        id_producto: item.id_producto,
        cantidad: item.cantidad
    }));

    const btn = this;
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Creando...';

    fetch('/api/ventas/pedidos/crear', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            items: items,
            id_cliente: idCliente      // puede ir null si es cliente normal
        })
    })
        .then(r => r.json())
        .then(data => {
            if (data.success) {
                if (data.id_factura) {
                    const pagarAhora = confirm('Pedido creado exitosamente. ¿Desea registrar el pago ahora?');
                    if (pagarAhora) {
                        abrirModalPagoInmediato(data.id_pedido, data.id_factura);
                    } else {
                        window.location.href = '/ventas/pedidos';
                    }
                } else {
                    alert('Pedido creado exitosamente. La factura se generará cuando el pedido cambie de estado.');
                    window.location.href = '/ventas/pedidos';
                }
            } else {
                alert(data.mensaje || 'Error al crear el pedido');
                btn.disabled = false;
                btn.innerHTML = '<i class="bi bi-check-circle"></i> Crear Pedido';
            }
        })
        .catch(err => {
            console.error('Error:', err);
            alert('Error al crear el pedido');
            btn.disabled = false;
            btn.innerHTML = '<i class="bi bi-check-circle"></i> Crear Pedido';
        });
});

// ========= PAGO INMEDIATO =========

function abrirModalPagoInmediato(idPedido, idFactura) {
    fetch('/api/ventas/pagos/metodos')
        .then(r => r.json())
        .then(metodos => {
            const selectMetodo = document.getElementById('pagoInmediatoMetodo');
            selectMetodo.innerHTML = '<option value="">Seleccione un método...</option>';
            metodos.forEach(metodo => {
                selectMetodo.innerHTML += `<option value="${metodo.id_metodo_pago}">${metodo.nombre_metodo_pago}</option>`;
            });

            document.getElementById('pagoInmediatoIdPedido').value = idPedido;
            document.getElementById('pagoInmediatoIdFactura').value = idFactura;

            fetch(`/api/ventas/facturas/${idFactura}/total`)
                .then(r => r.json())
                .then(data => {
                    if (data.total) {
                        document.getElementById('pagoInmediatoTotal').textContent =
                            '$' + parseFloat(data.total).toLocaleString('es-MX', { minimumFractionDigits: 2 });
                        document.getElementById('pagoInmediatoImporte').value = data.total;
                        document.getElementById('pagoInmediatoImporte').max = data.total;
                    }
                })
                .catch(err => console.error('Error obteniendo total:', err));

            const modal = new bootstrap.Modal(document.getElementById('modalPagoInmediato'));
            modal.show();
        })
        .catch(err => {
            console.error('Error obteniendo métodos de pago:', err);
            alert('Error al cargar métodos de pago');
        });
}

document.getElementById('btnRegistrarPagoInmediato').addEventListener('click', function () {
    const form = document.getElementById('formPagoInmediato');
    if (!form.checkValidity()) {
        form.reportValidity();
        return;
    }

    const data = {
        id_pedido: parseInt(document.getElementById('pagoInmediatoIdPedido').value),
        importe: parseFloat(document.getElementById('pagoInmediatoImporte').value),
        id_metodo_pago: parseInt(document.getElementById('pagoInmediatoMetodo').value)
    };

    const btn = this;
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Procesando...';

    fetch(`/api/ventas/pedidos/${data.id_pedido}/pagar`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            importe: data.importe,
            id_metodo_pago: data.id_metodo_pago
        })
    })
        .then(r => r.json())
        .then(data => {
            if (data.success) {
                alert(data.mensaje || 'Pago registrado exitosamente');
                window.location.href = '/ventas/pedidos';
            } else {
                alert('Error: ' + (data.mensaje || data.error || 'No se pudo registrar el pago'));
                btn.disabled = false;
                btn.innerHTML = '<i class="bi bi-credit-card"></i> Registrar Pago';
            }
        })
        .catch(err => {
            console.error('Error:', err);
            alert('Error al registrar el pago');
            btn.disabled = false;
            btn.innerHTML = '<i class="bi bi-credit-card"></i> Registrar Pago';
        });
});
