document.getElementById('registerForm').addEventListener('submit', function (e) {
    e.preventDefault();

    // Validar que las contraseñas coincidan
    const contrasena = document.getElementById('contrasena').value;
    const confirmar = document.getElementById('confirmar_contrasena').value;

    if (contrasena !== confirmar) {
        showAlert('Las contraseñas no coinciden', 'danger');
        return;
    }

    // Validaciones de campos según reglas solicitadas
    const username = document.getElementById('nombre_usuario').value.trim();
    const nombre1 = document.getElementById('nombre_primero').value.trim();
    const nombre2 = document.getElementById('nombre_segundo') ? document.getElementById('nombre_segundo').value.trim() : '';
    const apellido1 = document.getElementById('apellido_paterno').value.trim();
    const apellido2 = document.getElementById('apellido_materno') ? document.getElementById('apellido_materno').value.trim() : '';

    // username: only letters/numbers/underscore, no spaces or punctuation
    if (!/^[A-Za-z0-9_]+$/.test(username)) {
        showAlert('Nombre de usuario inválido: sólo letras, números y guión bajo, sin espacios.', 'danger');
        return;
    }

    // names and last names: only letters (no spaces, numbers or other chars), allow accented letters
    const nameRegex = /^[A-Za-zÀ-ÖØ-öø-ÿ]+$/;
    if (!nameRegex.test(nombre1)) { showAlert('Nombre inválido: sólo letras sin espacios.', 'danger'); return; }
    if (nombre2 && !nameRegex.test(nombre2)) { showAlert('Segundo nombre inválido: sólo letras sin espacios.', 'danger'); return; }
    if (!nameRegex.test(apellido1)) { showAlert('Apellido paterno inválido: sólo letras sin espacios.', 'danger'); return; }
    if (apellido2 && !nameRegex.test(apellido2)) { showAlert('Apellido materno inválido: sólo letras sin espacios.', 'danger'); return; }

    // Deshabilitar botón
    const btnRegister = document.getElementById('btnRegister');
    btnRegister.disabled = true;
    btnRegister.innerHTML = '<i class="bi bi-hourglass-split"></i> Procesando...';

    // Recopilar datos del formulario
    const formData = {
        nombre_usuario: document.getElementById('nombre_usuario').value.trim(),
        nombre_primero: document.getElementById('nombre_primero').value.trim(),
        nombre_segundo: nombre2 || null,
        apellido_paterno: apellido1,
        apellido_materno: apellido2 || null,
        correo: document.getElementById('correo').value.trim(),
        contrasena: contrasena,
        nombre_genero: document.getElementById('nombre_genero').value || null
    };

    // Enviar a la API
    fetch('/api/clientes/crear', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(formData)
    })
        .then(r => r.json())
        .then(data => {
            if (data.success) {
                // Si se creó la sesión automáticamente, redirigir al perfil del cliente
                if (data.session_created && data.redirect_url) {
                    // Guardar el carrito pendiente si existe antes de redirigir
                    const carritoPendiente = sessionStorage.getItem('carrito_pendiente');
                    if (carritoPendiente) {
                        console.log('[DEBUG] Registro: Carrito pendiente encontrado, se restaurará después del login');
                        // El carrito se restaurará automáticamente cuando se cargue la página de destino
                    }
                    
                    showAlert('¡Cuenta creada exitosamente! Redirigiendo a tu perfil...', 'success');
                    setTimeout(() => {
                        window.location.href = data.redirect_url;
                    }, 1500);
                } else {
                    // Si no se creó la sesión, redirigir al login
                    showAlert('¡Cuenta creada exitosamente! Redirigiendo al login...', 'success');
                    setTimeout(() => {
                        window.location.href = data.redirect_url || '/login';
                    }, 2000);
                }
            } else {
                showAlert(data.mensaje || data.error || 'Error al crear la cuenta', 'danger');
                btnRegister.disabled = false;
                btnRegister.innerHTML = '<i class="bi bi-person-plus"></i> Crear Cuenta';
            }
        })
        .catch(err => {
            console.error('Error:', err);
            showAlert('Error al crear la cuenta. Por favor, intenta de nuevo.', 'danger');
            btnRegister.disabled = false;
            btnRegister.innerHTML = '<i class="bi bi-person-plus"></i> Crear Cuenta';
        });
});

function showAlert(message, type) {
    const alertContainer = document.getElementById('alertContainer');
    alertContainer.innerHTML = ` 
        <div class="alert alert-${type} alert-dismissible fade show" role="alert">
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    `;
}
