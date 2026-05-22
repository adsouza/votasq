// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'notification_preferences.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NotificationPreferences {

 Map<String, ChannelPreferences> get perType;
/// Create a copy of NotificationPreferences
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NotificationPreferencesCopyWith<NotificationPreferences> get copyWith => _$NotificationPreferencesCopyWithImpl<NotificationPreferences>(this as NotificationPreferences, _$identity);

  /// Serializes this NotificationPreferences to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NotificationPreferences&&const DeepCollectionEquality().equals(other.perType, perType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(perType));

@override
String toString() {
  return 'NotificationPreferences(perType: $perType)';
}


}

/// @nodoc
abstract mixin class $NotificationPreferencesCopyWith<$Res>  {
  factory $NotificationPreferencesCopyWith(NotificationPreferences value, $Res Function(NotificationPreferences) _then) = _$NotificationPreferencesCopyWithImpl;
@useResult
$Res call({
 Map<String, ChannelPreferences> perType
});




}
/// @nodoc
class _$NotificationPreferencesCopyWithImpl<$Res>
    implements $NotificationPreferencesCopyWith<$Res> {
  _$NotificationPreferencesCopyWithImpl(this._self, this._then);

  final NotificationPreferences _self;
  final $Res Function(NotificationPreferences) _then;

/// Create a copy of NotificationPreferences
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? perType = null,}) {
  return _then(_self.copyWith(
perType: null == perType ? _self.perType : perType // ignore: cast_nullable_to_non_nullable
as Map<String, ChannelPreferences>,
  ));
}

}


/// Adds pattern-matching-related methods to [NotificationPreferences].
extension NotificationPreferencesPatterns on NotificationPreferences {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NotificationPreferences value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NotificationPreferences() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NotificationPreferences value)  $default,){
final _that = this;
switch (_that) {
case _NotificationPreferences():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NotificationPreferences value)?  $default,){
final _that = this;
switch (_that) {
case _NotificationPreferences() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, ChannelPreferences> perType)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NotificationPreferences() when $default != null:
return $default(_that.perType);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, ChannelPreferences> perType)  $default,) {final _that = this;
switch (_that) {
case _NotificationPreferences():
return $default(_that.perType);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, ChannelPreferences> perType)?  $default,) {final _that = this;
switch (_that) {
case _NotificationPreferences() when $default != null:
return $default(_that.perType);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NotificationPreferences implements NotificationPreferences {
  const _NotificationPreferences({final  Map<String, ChannelPreferences> perType = const <String, ChannelPreferences>{}}): _perType = perType;
  factory _NotificationPreferences.fromJson(Map<String, dynamic> json) => _$NotificationPreferencesFromJson(json);

 final  Map<String, ChannelPreferences> _perType;
@override@JsonKey() Map<String, ChannelPreferences> get perType {
  if (_perType is EqualUnmodifiableMapView) return _perType;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_perType);
}


/// Create a copy of NotificationPreferences
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NotificationPreferencesCopyWith<_NotificationPreferences> get copyWith => __$NotificationPreferencesCopyWithImpl<_NotificationPreferences>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NotificationPreferencesToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NotificationPreferences&&const DeepCollectionEquality().equals(other._perType, _perType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_perType));

@override
String toString() {
  return 'NotificationPreferences(perType: $perType)';
}


}

/// @nodoc
abstract mixin class _$NotificationPreferencesCopyWith<$Res> implements $NotificationPreferencesCopyWith<$Res> {
  factory _$NotificationPreferencesCopyWith(_NotificationPreferences value, $Res Function(_NotificationPreferences) _then) = __$NotificationPreferencesCopyWithImpl;
@override @useResult
$Res call({
 Map<String, ChannelPreferences> perType
});




}
/// @nodoc
class __$NotificationPreferencesCopyWithImpl<$Res>
    implements _$NotificationPreferencesCopyWith<$Res> {
  __$NotificationPreferencesCopyWithImpl(this._self, this._then);

  final _NotificationPreferences _self;
  final $Res Function(_NotificationPreferences) _then;

/// Create a copy of NotificationPreferences
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? perType = null,}) {
  return _then(_NotificationPreferences(
perType: null == perType ? _self._perType : perType // ignore: cast_nullable_to_non_nullable
as Map<String, ChannelPreferences>,
  ));
}


}


/// @nodoc
mixin _$ChannelPreferences {

 bool? get inApp; bool? get email; bool? get push;
/// Create a copy of ChannelPreferences
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChannelPreferencesCopyWith<ChannelPreferences> get copyWith => _$ChannelPreferencesCopyWithImpl<ChannelPreferences>(this as ChannelPreferences, _$identity);

  /// Serializes this ChannelPreferences to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChannelPreferences&&(identical(other.inApp, inApp) || other.inApp == inApp)&&(identical(other.email, email) || other.email == email)&&(identical(other.push, push) || other.push == push));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,inApp,email,push);

@override
String toString() {
  return 'ChannelPreferences(inApp: $inApp, email: $email, push: $push)';
}


}

/// @nodoc
abstract mixin class $ChannelPreferencesCopyWith<$Res>  {
  factory $ChannelPreferencesCopyWith(ChannelPreferences value, $Res Function(ChannelPreferences) _then) = _$ChannelPreferencesCopyWithImpl;
@useResult
$Res call({
 bool? inApp, bool? email, bool? push
});




}
/// @nodoc
class _$ChannelPreferencesCopyWithImpl<$Res>
    implements $ChannelPreferencesCopyWith<$Res> {
  _$ChannelPreferencesCopyWithImpl(this._self, this._then);

  final ChannelPreferences _self;
  final $Res Function(ChannelPreferences) _then;

/// Create a copy of ChannelPreferences
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? inApp = freezed,Object? email = freezed,Object? push = freezed,}) {
  return _then(_self.copyWith(
inApp: freezed == inApp ? _self.inApp : inApp // ignore: cast_nullable_to_non_nullable
as bool?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as bool?,push: freezed == push ? _self.push : push // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChannelPreferences].
extension ChannelPreferencesPatterns on ChannelPreferences {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChannelPreferences value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChannelPreferences() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChannelPreferences value)  $default,){
final _that = this;
switch (_that) {
case _ChannelPreferences():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChannelPreferences value)?  $default,){
final _that = this;
switch (_that) {
case _ChannelPreferences() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool? inApp,  bool? email,  bool? push)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChannelPreferences() when $default != null:
return $default(_that.inApp,_that.email,_that.push);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool? inApp,  bool? email,  bool? push)  $default,) {final _that = this;
switch (_that) {
case _ChannelPreferences():
return $default(_that.inApp,_that.email,_that.push);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool? inApp,  bool? email,  bool? push)?  $default,) {final _that = this;
switch (_that) {
case _ChannelPreferences() when $default != null:
return $default(_that.inApp,_that.email,_that.push);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChannelPreferences implements ChannelPreferences {
  const _ChannelPreferences({this.inApp, this.email, this.push});
  factory _ChannelPreferences.fromJson(Map<String, dynamic> json) => _$ChannelPreferencesFromJson(json);

@override final  bool? inApp;
@override final  bool? email;
@override final  bool? push;

/// Create a copy of ChannelPreferences
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChannelPreferencesCopyWith<_ChannelPreferences> get copyWith => __$ChannelPreferencesCopyWithImpl<_ChannelPreferences>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChannelPreferencesToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChannelPreferences&&(identical(other.inApp, inApp) || other.inApp == inApp)&&(identical(other.email, email) || other.email == email)&&(identical(other.push, push) || other.push == push));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,inApp,email,push);

@override
String toString() {
  return 'ChannelPreferences(inApp: $inApp, email: $email, push: $push)';
}


}

/// @nodoc
abstract mixin class _$ChannelPreferencesCopyWith<$Res> implements $ChannelPreferencesCopyWith<$Res> {
  factory _$ChannelPreferencesCopyWith(_ChannelPreferences value, $Res Function(_ChannelPreferences) _then) = __$ChannelPreferencesCopyWithImpl;
@override @useResult
$Res call({
 bool? inApp, bool? email, bool? push
});




}
/// @nodoc
class __$ChannelPreferencesCopyWithImpl<$Res>
    implements _$ChannelPreferencesCopyWith<$Res> {
  __$ChannelPreferencesCopyWithImpl(this._self, this._then);

  final _ChannelPreferences _self;
  final $Res Function(_ChannelPreferences) _then;

/// Create a copy of ChannelPreferences
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? inApp = freezed,Object? email = freezed,Object? push = freezed,}) {
  return _then(_ChannelPreferences(
inApp: freezed == inApp ? _self.inApp : inApp // ignore: cast_nullable_to_non_nullable
as bool?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as bool?,push: freezed == push ? _self.push : push // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

// dart format on
