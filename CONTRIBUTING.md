# 🤝 Guía Esencial de Contribución

-----

## Flujo de Trabajo Rápido 🌿

### A. Preparación:

  * **Sincronizar `main`:** Asegúrate de tener lo último del repositorio principal.
    ```bash
    git checkout main
    git pull origin main
    ```
  * **Crear Rama:** Usa una rama nueva para **cada** cambio (ej: `feat/mi-cambio`).
    ```bash
    git checkout -b tu-rama
    ```

-----

### B. Trabajo y Envío:

1.  **Hacer Cambios.** Todos los cambios que realices git los rastreará.
2.  **Confirmar:** Haz *commits atómicos* y claros.
    ```bash
    git add .
    git commit -m "feat: Describe tu cambio en imperativo"
    ```
3.  **Empujar:** Sube tu rama a tu repositorio remoto (`origin`).
    ```bash
    git push origin tu-rama`;`
    ```
4.  **Abrir PR:** Crea una Solicitud de Extracción (Pull Request) en la interfaz web de GitHub desde `tu-rama` hacia `main`.

-----

### C. Actualizar un PR Abierto:

  * Si necesitas hacer más cambios después de abrir el PR, **simplemente añade nuevos commits** a la misma rama y vuelve a empujar. El PR se actualizará automáticamente.
    ```bash
    # (Hacer cambios adicionales)
    git add .
    git commit -m "fix: Añade corrección solicitada"
    git push origin tu-rama
    ```
    
-----

### D. Crear la Solicitud de Extracción (Pull Request) 🚀

Esta es la forma de pedirle formalmente al autor del proyecto que incorpore tus cambios.

1.  **Navega a GitHub:** Abre tu navegador y ve a la página principal del **repositorio de tu *fork** en GitHub (es decir, el repositorio en tu propia cuenta).
2.  **Detección Automática:** GitHub usualmente detecta que has empujado una rama nueva y mostrará un botón o un banner grande que dice:
    * **"Compare & pull request"** o **"Compare & Review"**. ¡Haz clic ahí! 
3.  **Configura el PR:**
    * **Base Repository (Repositorio Base):** Debe ser el repositorio original (`upstream`) de tu amigo.
    * **Base Branch (Rama Base):** Debe ser la rama a la que quieres fusionar (casi siempre `main`).
    * **Head Repository (Repositorio Head):** Debe ser tu *fork*.
    * **Head Branch (Rama Head):** Debe ser la rama que acabas de subir (`tu-rama`).
4.  **Añade Descripción:**
    * Escribe un **Título** claro y conciso para el PR (ej: "feat: Implementar nueva función de logueo").
    * Añade una **Descripción** detallada sobre qué problema resuelve tu código y cómo lo hiciste.
5.  **Enviar PR:** Haz clic en **"Create pull request"**.
