// Si no hay categorías cargadas desde el backend, cargarlas desde la API
document.addEventListener('DOMContentLoaded', function () {
    console.log('DOM cargado, inicializando formulario...');

    // Prevenir cualquier envío del formulario
    const form = document.getElementById('formCrearProducto');
    if (form) {
        form.removeAttribute('action');
        form.removeAttribute('method');
        form.setAttribute('onsubmit', 'event.preventDefault(); event.stopPropagation(); return false;');

        // Prevenir envío de múltiples formas
        form.addEventListener('submit', function (e) {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
            return false;
        }, true); // Usar capture phase para interceptar antes
    }

    const selectCategoria = document.getElementById('categoria');
    const selectMaterial = document.getElementById('material');
    const tallaContainer = document.getElementById('talla-container');
    const kilatajeContainer = document.getElementById('kilataje-container');
    const leyContainer = document.getElementById('ley-container');

    // Si el select solo tiene la opción por defecto, cargar desde API
    if (selectCategoria && selectCategoria.options.length <= 1) {
        fetch('/api/categorias/activas')
            .then(r => r.json())
            .then(data => {
                if (data && !data.error) {
                    data.forEach(categoria => {
                        const option = document.createElement('option');
                        option.value = categoria.nombre_categoria;
                        option.textContent = categoria.nombre_categoria;
                        selectCategoria.appendChild(option);
                    });
                }
            })
            .catch(err => {
                console.error('Error cargando categorías:', err);
            });
    }

    // Mostrar/ocultar campos según categoría seleccionada
    if (selectCategoria) {
        selectCategoria.addEventListener('change', function () {
            const categoria = this.value.toLowerCase();
            if (categoria === 'anillos') {
                tallaContainer.style.display = 'block';
                document.getElementById('talla').required = true;
            } else {
                tallaContainer.style.display = 'none';
                document.getElementById('talla').required = false;
                document.getElementById('talla').value = '';
            }
        });
    }

    // Mostrar/ocultar campos según material seleccionado
    if (selectMaterial) {
        selectMaterial.addEventListener('change', function () {
            const material = this.value.toLowerCase();
            if (material === 'oro') {
                kilatajeContainer.style.display = 'block';
                leyContainer.style.display = 'none';
                document.getElementById('kilataje').required = true;
                document.getElementById('ley').required = false;
                document.getElementById('ley').value = '';
            } else if (material === 'plata') {
                kilatajeContainer.style.display = 'none';
                leyContainer.style.display = 'block';
                document.getElementById('kilataje').required = false;
                document.getElementById('ley').required = true;
                document.getElementById('kilataje').value = '';
            } else {
                kilatajeContainer.style.display = 'none';
                leyContainer.style.display = 'none';
                document.getElementById('kilataje').required = false;
                document.getElementById('ley').required = false;
                document.getElementById('kilataje').value = '';
                document.getElementById('ley').value = '';
            }
        });
    }

    // Manejar el envío del formulario
    const btnGuardar = document.getElementById('btnGuardarProducto');

    function enviarFormulario() {

        // Recolectar datos del formulario
        let skuValue = document.getElementById('sku').value.trim();
        console.log('SKU antes de validar:', skuValue, 'Longitud:', skuValue.length);

        const formData = {
            sku: skuValue,
            nombre_producto: document.getElementById('nombre_producto').value.trim(),
            nombre_categoria: document.getElementById('categoria').value.trim(),
            material: document.getElementById('material').value.trim(),
            genero_producto: document.getElementById('genero_producto').value.trim(),
            precio_unitario: parseFloat(document.getElementById('precio_unitario').value) || null,
            descuento_producto: parseInt(document.getElementById('descuento_producto').value) || 0,
            costo_unitario: parseFloat(document.getElementById('costo_unitario').value) || null
        };

        // Campos opcionales
        const talla = document.getElementById('talla')?.value.trim();
        if (talla) formData.talla = parseInt(talla);

        const kilataje = document.getElementById('kilataje')?.value.trim();
        if (kilataje) formData.kilataje = kilataje;

        const ley = document.getElementById('ley')?.value.trim();
        if (ley) formData.ley = ley;

        // Validaciones básicas
        if (!formData.sku || !formData.nombre_producto || !formData.nombre_categoria ||
            !formData.material || !formData.genero_producto) {
            alert('Por favor complete todos los campos requeridos');
            return;
        }

        // Normalizar SKU (similar al stored procedure)
        let skuNormalizado = formData.sku.toUpperCase().trim();
        skuNormalizado = skuNormalizado.replace(/AUR/g, 'AUR-');
        skuNormalizado = skuNormalizado.replace(/\s+/g, '');
        
        if (!skuNormalizado.startsWith('AUR-')) {
            skuNormalizado = 'AUR-' + skuNormalizado;
        }
        
        // Validar formato del SKU: AUR- seguido de 3 dígitos y una letra (total 8 caracteres)
        const skuPattern = /^AUR-[0-9]{3}[A-Za-z]$/;
        if (!skuPattern.test(skuNormalizado)) {
            alert('Formato de SKU inválido. El formato debe ser: AUR-999X\n\nEjemplos válidos:\n- AUR-001A\n- AUR-123B\n- AUR-999Z\n\nEl SKU debe tener exactamente 8 caracteres: AUR- seguido de 3 dígitos y una letra.');
            document.getElementById('sku').focus();
            return;
        }
        
        if (skuNormalizado.length !== 8) {
            alert(`El SKU debe tener exactamente 8 caracteres. El SKU normalizado tiene ${skuNormalizado.length} caracteres: "${skuNormalizado}"\n\nFormato requerido: AUR-999X`);
            document.getElementById('sku').focus();
            return;
        }
        
        // Usar el SKU normalizado
        formData.sku = skuNormalizado;
        console.log('SKU normalizado:', formData.sku);

        if (formData.precio_unitario === null || formData.costo_unitario === null) {
            alert('Precio y costo son requeridos');
            return;
        }

        // Validar campos condicionales
        if (formData.nombre_categoria.toLowerCase() === 'anillos' && !formData.talla) {
            alert('Debe especificar la talla para productos tipo Anillos');
            return;
        }

        if (formData.material.toLowerCase() === 'oro' && !formData.kilataje) {
            alert('Debe especificar el kilataje para productos de Oro');
            return;
        }

        if (formData.material.toLowerCase() === 'plata' && !formData.ley) {
            alert('Debe especificar la ley para productos de Plata');
            return;
        }

        // Deshabilitar botón de envío
        const submitBtn = document.getElementById('btnGuardarProducto');
        const originalText = submitBtn.innerHTML;
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Guardando...';

        // Enviar a la API
        fetch('/api/productos/crear', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(formData)
        })
            .then(response => response.json())
            .then(data => {
                if (data.error) {
                    alert('Error: ' + (data.mensaje || data.error));
                    submitBtn.disabled = false;
                    submitBtn.innerHTML = originalText;
                } else {
                    alert('Producto creado exitosamente');
                    window.location.href = '/admin/productos';
                }
            })
            .catch(error => {
                console.error('Error:', error);
                alert('Error al crear el producto. Por favor intente nuevamente.');
                submitBtn.disabled = false;
                submitBtn.innerHTML = originalText;
            });
    }

    // Asignar el evento al botón
    if (btnGuardar) {
        console.log('Botón encontrado, asignando evento click');
        btnGuardar.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            console.log('Click en botón guardar');
            enviarFormulario();
        });
    } else {
        console.error('ERROR: No se encontró el botón btnGuardarProducto');
    }

    // También manejar el submit del formulario por si acaso
    if (form) {
        console.log('Form encontrado, asignando evento submit');
        form.addEventListener('submit', function (e) {
            console.log('Submit interceptado');
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
            enviarFormulario();
            return false;
        }, true);
    } else {
        console.error('ERROR: No se encontró el formulario formCrearProducto');
    }
});
