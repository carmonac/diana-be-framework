/// `TypeChecker`s for every Diana annotation. Checking is assignability-based,
/// so `@Service` etc. match the `Injectable` checker.
library;

import 'package:source_gen/source_gen.dart';

const String _base = 'package:diana_annotation/src';

// DI
const injectableChecker = TypeChecker.fromUrl('$_base/di.dart#Injectable');
const namedChecker = TypeChecker.fromUrl('$_base/di.dart#Named');

// Web
const restControllerChecker =
    TypeChecker.fromUrl('$_base/web.dart#RestController');
const httpRouteChecker = TypeChecker.fromUrl('$_base/web.dart#HttpRoute');
const pathParamChecker = TypeChecker.fromUrl('$_base/web.dart#PathParam');
const queryParamChecker = TypeChecker.fromUrl('$_base/web.dart#QueryParam');
const headerChecker = TypeChecker.fromUrl('$_base/web.dart#Header');
const bodyChecker = TypeChecker.fromUrl('$_base/web.dart#Body');
const responseStatusChecker =
    TypeChecker.fromUrl('$_base/web.dart#ResponseStatus');
const crossOriginChecker = TypeChecker.fromUrl('$_base/web.dart#CrossOrigin');
const consumesChecker = TypeChecker.fromUrl('$_base/web.dart#Consumes');
const producesChecker = TypeChecker.fromUrl('$_base/web.dart#Produces');

// gRPC
const grpcServiceChecker = TypeChecker.fromUrl('$_base/grpc.dart#GrpcService');

// JSON
const jsonChecker = TypeChecker.fromUrl('$_base/json.dart#Json');
const jsonFieldChecker = TypeChecker.fromUrl('$_base/json.dart#JsonField');

// Lifecycle
const postConstructChecker =
    TypeChecker.fromUrl('$_base/lifecycle.dart#PostConstruct');
const preDestroyChecker =
    TypeChecker.fromUrl('$_base/lifecycle.dart#PreDestroy');

// Scheduling
const scheduledChecker =
    TypeChecker.fromUrl('$_base/scheduling.dart#Scheduled');

// Events
const eventListenerChecker =
    TypeChecker.fromUrl('$_base/events.dart#EventListener');

// Auth
const securedChecker = TypeChecker.fromUrl('$_base/auth.dart#Secured');
const rolesAllowedChecker =
    TypeChecker.fromUrl('$_base/auth.dart#RolesAllowed');
const principalChecker = TypeChecker.fromUrl('$_base/auth.dart#Principal');

// Data
const transactionalChecker =
    TypeChecker.fromUrl('$_base/data.dart#Transactional');
const tableChecker = TypeChecker.fromUrl('$_base/data.dart#Table');

// Aspects
const timedChecker = TypeChecker.fromUrl('$_base/aspects.dart#Timed');
const cacheableChecker = TypeChecker.fromUrl('$_base/aspects.dart#Cacheable');
const retryableChecker = TypeChecker.fromUrl('$_base/aspects.dart#Retryable');
const circuitBreakerChecker =
    TypeChecker.fromUrl('$_base/aspects.dart#CircuitBreaker');

// WebSocket
const webSocketControllerChecker =
    TypeChecker.fromUrl('$_base/websocket.dart#WebSocketController');

// Middleware
const globalMiddlewareChecker =
    TypeChecker.fromUrl('$_base/middleware.dart#GlobalMiddleware');
const useMiddlewareChecker =
    TypeChecker.fromUrl('$_base/middleware.dart#UseMiddleware');

// Config
const valueChecker = TypeChecker.fromUrl('$_base/config.dart#Value');
const configPropsChecker =
    TypeChecker.fromUrl('$_base/config.dart#ConfigurationProperties');

// Exceptions
const controllerAdviceChecker =
    TypeChecker.fromUrl('$_base/exceptions.dart#ControllerAdvice');
const exceptionHandlerChecker =
    TypeChecker.fromUrl('$_base/exceptions.dart#ExceptionHandler');

// App
const dianaApplicationChecker =
    TypeChecker.fromUrl('$_base/app.dart#DianaApplication');

// Validation
const notNullChecker = TypeChecker.fromUrl('$_base/validation.dart#NotNull');
const notEmptyChecker = TypeChecker.fromUrl('$_base/validation.dart#NotEmpty');
const notBlankChecker = TypeChecker.fromUrl('$_base/validation.dart#NotBlank');
const minChecker = TypeChecker.fromUrl('$_base/validation.dart#Min');
const maxChecker = TypeChecker.fromUrl('$_base/validation.dart#Max');
const sizeChecker = TypeChecker.fromUrl('$_base/validation.dart#Size');
const patternChecker = TypeChecker.fromUrl('$_base/validation.dart#Pattern');
const emailChecker = TypeChecker.fromUrl('$_base/validation.dart#Email');
const validChecker = TypeChecker.fromUrl('$_base/validation.dart#Valid');

/// Any constraint checker (everything except `@Valid`).
const constraintCheckers = <TypeChecker>[
  notNullChecker,
  notEmptyChecker,
  notBlankChecker,
  minChecker,
  maxChecker,
  sizeChecker,
  patternChecker,
  emailChecker,
];
