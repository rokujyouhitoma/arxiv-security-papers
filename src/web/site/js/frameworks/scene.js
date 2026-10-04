(function() {
  'use strict';

/**
 * Base Scene Class
 * @implements {SceneInterface}
 */
class Scene {
    /**
     * Enter the scene.
     * @param {*=} data Optional context data passed to the scene.
     * @override
     */
    // @ts-expect-error
    enter(data) {
        throw new Error("enter() must be implemented");
    }

    /**
     * Exit the scene.
     * @override
     */
    // @ts-expect-error
    exit() {
        throw new Error("exit() must be implemented");
    }
}

/**
 * SceneDirector manages the transitions between scenes
 * @implements {SceneDirectorInterface}
 */
class SceneDirector {
    constructor() {
        /**
         * Registered Scenes
         * @private
         * @type {!Object<string, !SceneInterface>}
         */
        this.scenes = {};

        /**
         * Current Active Scene Name
         * @public
         * @type {?string}
         */
        this.currentSceneName = null;

        /**
         * Transition Guard Flag
         * @public
         * @type {boolean}
         */
        this.isTransitioning = false;
    }

    /**
     * Register a scene.
     * @param {string} sceneName
     * @param {!SceneInterface} sceneInstance
     * @override
     */
    // @ts-expect-error
    register(sceneName, sceneInstance) {
        this.scenes[sceneName] = sceneInstance;
    }

    /**
     * Transition to the specified scene.
     * @param {string} sceneName Name of the target scene.
     * @param {*=} data Data payload to pass to the scene enter lifecycle.
     * @override
     */
    // @ts-expect-error
    transitionTo(sceneName, data) {
        if (this.isTransitioning) {
            return;
        }

        const nextScene = this.scenes[sceneName];
        if (!nextScene) {
            throw new Error(`Scene not found: ${sceneName}`);
        }

        this.isTransitioning = true;

        try {
            if (this.currentSceneName) {
                const currentScene = this.scenes[this.currentSceneName];
                currentScene.exit();
            }

            this.currentSceneName = sceneName;
            nextScene.enter(data);
        } finally {
            this.isTransitioning = false;
        }
    }
}

  // Export to global scope & Application frameworks namespace
  if (typeof window !== 'undefined') {
    window.Scene = Scene;
    window.SceneDirector = SceneDirector;

    window.Application = window.Application || {};
    window.Application.frameworks = window.Application.frameworks || {};
    window.Application.frameworks.Scene = Scene;
    window.Application.frameworks.SceneDirector = SceneDirector;
    window.App = window.Application;
    window.yuzora = window.Application;
  }

  // Export for Node.js / CommonJS testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      Scene: Scene,
      SceneDirector: SceneDirector
    };
  }
})();
