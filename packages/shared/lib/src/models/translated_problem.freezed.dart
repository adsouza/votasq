// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'translated_problem.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TranslatedProblem {

 String get description; String get goal;
/// Create a copy of TranslatedProblem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TranslatedProblemCopyWith<TranslatedProblem> get copyWith => _$TranslatedProblemCopyWithImpl<TranslatedProblem>(this as TranslatedProblem, _$identity);

  /// Serializes this TranslatedProblem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TranslatedProblem&&(identical(other.description, description) || other.description == description)&&(identical(other.goal, goal) || other.goal == goal));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,description,goal);

@override
String toString() {
  return 'TranslatedProblem(description: $description, goal: $goal)';
}


}

/// @nodoc
abstract mixin class $TranslatedProblemCopyWith<$Res>  {
  factory $TranslatedProblemCopyWith(TranslatedProblem value, $Res Function(TranslatedProblem) _then) = _$TranslatedProblemCopyWithImpl;
@useResult
$Res call({
 String description, String goal
});




}
/// @nodoc
class _$TranslatedProblemCopyWithImpl<$Res>
    implements $TranslatedProblemCopyWith<$Res> {
  _$TranslatedProblemCopyWithImpl(this._self, this._then);

  final TranslatedProblem _self;
  final $Res Function(TranslatedProblem) _then;

/// Create a copy of TranslatedProblem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? description = null,Object? goal = null,}) {
  return _then(_self.copyWith(
description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TranslatedProblem].
extension TranslatedProblemPatterns on TranslatedProblem {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TranslatedProblem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TranslatedProblem() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TranslatedProblem value)  $default,){
final _that = this;
switch (_that) {
case _TranslatedProblem():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TranslatedProblem value)?  $default,){
final _that = this;
switch (_that) {
case _TranslatedProblem() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String description,  String goal)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TranslatedProblem() when $default != null:
return $default(_that.description,_that.goal);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String description,  String goal)  $default,) {final _that = this;
switch (_that) {
case _TranslatedProblem():
return $default(_that.description,_that.goal);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String description,  String goal)?  $default,) {final _that = this;
switch (_that) {
case _TranslatedProblem() when $default != null:
return $default(_that.description,_that.goal);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TranslatedProblem implements TranslatedProblem {
  const _TranslatedProblem({required this.description, this.goal = ''});
  factory _TranslatedProblem.fromJson(Map<String, dynamic> json) => _$TranslatedProblemFromJson(json);

@override final  String description;
@override@JsonKey() final  String goal;

/// Create a copy of TranslatedProblem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TranslatedProblemCopyWith<_TranslatedProblem> get copyWith => __$TranslatedProblemCopyWithImpl<_TranslatedProblem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TranslatedProblemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TranslatedProblem&&(identical(other.description, description) || other.description == description)&&(identical(other.goal, goal) || other.goal == goal));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,description,goal);

@override
String toString() {
  return 'TranslatedProblem(description: $description, goal: $goal)';
}


}

/// @nodoc
abstract mixin class _$TranslatedProblemCopyWith<$Res> implements $TranslatedProblemCopyWith<$Res> {
  factory _$TranslatedProblemCopyWith(_TranslatedProblem value, $Res Function(_TranslatedProblem) _then) = __$TranslatedProblemCopyWithImpl;
@override @useResult
$Res call({
 String description, String goal
});




}
/// @nodoc
class __$TranslatedProblemCopyWithImpl<$Res>
    implements _$TranslatedProblemCopyWith<$Res> {
  __$TranslatedProblemCopyWithImpl(this._self, this._then);

  final _TranslatedProblem _self;
  final $Res Function(_TranslatedProblem) _then;

/// Create a copy of TranslatedProblem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? description = null,Object? goal = null,}) {
  return _then(_TranslatedProblem(
description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,goal: null == goal ? _self.goal : goal // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
