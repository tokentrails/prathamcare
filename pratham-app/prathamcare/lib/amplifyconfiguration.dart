import 'dart:convert';

const String _cognitoRegion = String.fromEnvironment('COGNITO_REGION', defaultValue: 'ap-south-1');
const String _cognitoUserPoolId = String.fromEnvironment(
  'COGNITO_USER_POOL_ID',
  defaultValue: 'ap-south-1_er3QpP9Ag',
);
const String _cognitoClientId = String.fromEnvironment(
  'COGNITO_CLIENT_ID',
  defaultValue: '2s2l3du92poeh09rhkpk3o6bom',
);

String buildAmplifyConfig() {
  final config = {
    'auth': {
      'plugins': {
        'awsCognitoAuthPlugin': {
          'CognitoUserPool': {
            'Default': {
              'PoolId': _cognitoUserPoolId,
              'AppClientId': _cognitoClientId,
              'Region': _cognitoRegion,
            },
          },
          'Auth': {
            'Default': {
              'authenticationFlowType': 'USER_PASSWORD_AUTH',
            },
          },
        },
      },
    },
  };

  return jsonEncode(config);
}
