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
