/**
 * Generic Publish/Subscribe Publisher Module
 */
"use strict";

/**
 * Publisher class.
 * @implements {PublisherInterface}
 */
class Publisher {
    /**
     * @param {!YuzoraEventTargetInterface} eventTarget The underlying event target.
     */
    constructor(eventTarget) {
        /**
         * @private
         * @type {!YuzoraEventTargetInterface}
         */
        this.eventTarget_ = eventTarget;

        /**
         * Map subscriber callbacks to event listener wrappers.
         * @private
         * @type {!Map<string, !Map<function(*): void, function(!YuzoraEventInterface): void>>}
         */
        this.wrappers_ = new Map();
    }

    /**
     * Subscribe to a topic.
     * @param {string} topic The topic to subscribe to.
     * @param {function(*): void} callback The callback function when the topic is published.
     * @override
     */
    // @ts-expect-error
    subscribe(topic, callback) {
        let topicMap = this.wrappers_.get(topic);
        if (!topicMap) {
            topicMap = new Map();
            this.wrappers_.set(topic, topicMap);
        }

        // Avoid duplicate subscriptions of the exact same callback for the same topic
        if (topicMap.has(callback)) {
            return;
        }

        /** @type {function(!YuzoraEventInterface): void} */
        const wrapper = (event) => {
            callback(event.detail);
        };
        topicMap.set(callback, wrapper);
        this.eventTarget_.addEventListener(topic, wrapper);
    }

    /**
     * Unsubscribe from a topic.
     * @param {string} topic The topic to unsubscribe from.
     * @param {function(*): void} callback The callback function.
     * @override
     */
    // @ts-expect-error
    unsubscribe(topic, callback) {
        const topicMap = this.wrappers_.get(topic);
        if (!topicMap) return;

        const wrapper = topicMap.get(callback);
        if (wrapper) {
            this.eventTarget_.removeEventListener(topic, wrapper);
            topicMap.delete(callback);
        }
        if (topicMap.size === 0) {
            this.wrappers_.delete(topic);
        }
    }

    /**
     * Publish data to all subscribers of a topic.
     * @param {string} topic The topic to publish.
     * @param {*=} data The data payload.
     * @override
     */
    // @ts-expect-error
    publish(topic, data) {
        // AppEvent is loaded globally before Publisher
        this.eventTarget_.dispatchEvent(/** @type {!YuzoraEventInterface} */ (new AppEvent(topic, data)));
    }

    /**
     * Publish data to all subscribers of a topic asynchronously on the next macro task.
     * @param {string} topic The topic to publish.
     * @param {*=} data The data payload.
     * @override
     */
    // @ts-expect-error
    publishAsync(topic, data) {
        setTimeout(() => {
            this.publish(topic, data);
        }, 0);
    }
}
