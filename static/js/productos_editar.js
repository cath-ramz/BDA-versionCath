// Función para mostrar/ocultar campo de talla según categoría
function toggleTallaField() {
    const categoria = document.getElementById('categoria').value;
    const tallaContainer = document.getElementById('talla-container');
    const tallaInput = document.getElementById('talla');

    // Mostrar solo si la categoría es "Anillos" o si está seleccionada "Anillos" en el select
    // También verificar la categoría actual del producto si no se ha cambiado
    // Note: categoriaActual needs to be passed from the template or handled differently if pure JS file
    // For now, we'll assume the value is correctly populated in the select element on load

    // Check if the select has a value, if not try to infer from context or default
    // In the HTML, the select is populated with the current category selected.

    const esAnillos = categoria === 'Anillos';

    if (esAnillos) {
        tallaContainer.style.display = 'block';
        tallaInput.required = true;
    } else {
        tallaContainer.style.display = 'none';
        tallaInput.required = false;
        tallaInput.value = ''; // Limpiar el valor si no es anillo
    }
}

// Mostrar/ocultar campo de talla al cambiar la categoría
document.getElementById('categoria').addEventListener('change', toggleTallaField);

// Verificar estado inicial al cargar la página
document.addEventListener('DOMContentLoaded', function () {
    toggleTallaField();
});

// Mostrar/ocultar campos según material seleccionado
document.getElementById('material').addEventListener('change', function () {
    const material = this.value;
    const oroFields = document.getElementById('oroFields');
    const plataFields = document.getElementById('plataFields');

    if (material === 'Oro') {
        oroFields.style.display = 'block';
        plataFields.style.display = 'none';
    } else if (material === 'Plata') {
        oroFields.style.display = 'none';
        plataFields.style.display = 'block';
    } else {
        oroFields.style.display = 'none';
        plataFields.style.display = 'none';
    }
});

// Manejar envío del formulario
document.getElementById('formEditarProducto').addEventListener('submit', function (e) {
    e.preventDefault();

    const formData = {
        sku: document.getElementById('sku').value,
        nombre_producto: document.getElementById('nombre_producto').value || null,
        nombre_categoria: document.getElementById('categoria').value || null,
        material: document.getElementById('material').value || null,
        genero_producto: document.getElementById('genero_producto').value || null,
        precio_unitario: document.getElementById('precio_unitario').value || null,
        descuento_producto: document.getElementById('descuento_producto').value || null,
        costo_unitario: document.getElementById('costo_unitario').value || null,
        talla: document.getElementById('talla').value || null,
        kilataje: document.getElementById('kilataje').value || null,
        ley: document.getElementById('ley').value || null,
        activo_producto: document.getElementById('activo_producto').checked
    };

    // Limpiar valores vacíos
    Object.keys(formData).forEach(key => {
        if (formData[key] === '' || formData[key] === null) {
            formData[key] = null;
        }
    });

    fetch('/api/productos/actualizar', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(formData)
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                alert('Producto actualizado exitosamente');
                window.location.href = '/admin/catalogo';
            } else {
                alert(data.message || 'Error al actualizar el producto');
            }
        })
        .catch(error => {
            console.error('Error:', error);
            alert('Error al actualizar el producto');
        });
});
