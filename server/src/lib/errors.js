export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function asyncHandler(fn) {
  return async function wrapped(req, res, next) {
    try {
      await fn(req, res, next);
    } catch (error) {
      next(error);
    }
  };
}
