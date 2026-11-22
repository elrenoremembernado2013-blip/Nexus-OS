(() => {
  const nativeServices = new Map();
  const knownServiceIds = new Set([
    "display",
    "sound",
    "network",
    "bluetooth",
    "power",
    "accounts",
    "privacy-security",
    "packages",
    "telemetry",
    "notifications",
    "files",
  ]);

  class NativeIntegrationUnavailableError extends Error {
    constructor(serviceId) {
      super(`Native service unavailable: ${serviceId}`);
      this.name = "NativeIntegrationUnavailableError";
      this.serviceId = serviceId;
      this.code = "NATIVE_SERVICE_UNAVAILABLE";
    }
  }

  window.NexusNativeServices = {
    register(serviceId, adapter) {
      if (!knownServiceIds.has(serviceId)) throw new RangeError(`Unknown native service: ${serviceId}`);
      if (!adapter || typeof adapter !== "object") throw new TypeError("A native service adapter must be an object.");
      if (nativeServices.has(serviceId)) throw new Error(`Native service already registered: ${serviceId}`);
      nativeServices.set(serviceId, Object.freeze({ ...adapter }));
      return true;
    },
    unregister(serviceId) {
      if (!knownServiceIds.has(serviceId)) throw new RangeError(`Unknown native service: ${serviceId}`);
      nativeServices.delete(serviceId);
      return true;
    },
    status(serviceId) {
      if (!knownServiceIds.has(serviceId)) throw new RangeError(`Unknown native service: ${serviceId}`);
      return {
        serviceId,
        available: nativeServices.has(serviceId),
      };
    },
    call(serviceId, methodName, ...args) {
      const adapter = nativeServices.get(serviceId);
      if (!adapter) throw new NativeIntegrationUnavailableError(serviceId);
      const method = adapter[methodName];
      if (typeof method !== "function") throw new TypeError(`Native service ${serviceId} does not provide ${methodName}.`);
      return method(...args);
    },
  };

  window.NativeIntegrationUnavailableError = NativeIntegrationUnavailableError;
})();
