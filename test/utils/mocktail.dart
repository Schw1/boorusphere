import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';

void setupMocktailFallbacks() {
  registerFallbackValue(RequestOptions());
}
