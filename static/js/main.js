// Utilidades para validación
function validarEmail(email) {
    const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return regex.test(email);
}

function validarTelefono(telefono) {
    const regex = /^[0-9]{7,}$/;
    return regex.test(telefono);
}

function validarFormulario(formId) {
    const form = document.getElementById(formId);
    if (!form) return false;
    
    const inputs = form.querySelectorAll('input[required], textarea[required], select[required]');
    let valido = true;
    
    inputs.forEach(input => {
        if (!input.value.trim()) {
            input.classList.add('is-invalid');
            valido = false;
        } else {
            input.classList.remove('is-invalid');
        }
    });
    
    return valido;
}

// Auto-cerrar alertas después de 5 segundos
document.querySelectorAll('.alert').forEach(alert => {
    setTimeout(() => {
        alert.style.transition = 'opacity 0.3s ease';
        alert.style.opacity = '0';
        setTimeout(() => alert.remove(), 300);
    }, 5000);
});

// Prevenir envío doble de formularios
// Excluir formularios que se manejan completamente con JavaScript (como formCrearProducto)
document.querySelectorAll('form').forEach(form => {
    // Saltar formularios que tienen onsubmit="return false;" o que tienen un ID específico que se maneja con JS
    if (form.id === 'formCrearProducto' || form.getAttribute('onsubmit')?.includes('return false')) {
        return; // No agregar listener a este formulario
    }
    
    form.addEventListener('submit', function() {
        // Solo deshabilitar botones, no prevenir el envío (dejamos que el formulario se envíe normalmente)
        this.querySelectorAll('button[type="submit"]').forEach(btn => {
            btn.disabled = true;
            btn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Enviando...';
        });
    });
});
