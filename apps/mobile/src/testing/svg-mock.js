// Los SVG no aportan a las pruebas: se reemplazan por vistas vacías.
const React = require('react');
const { View } = require('react-native');

const Stub = (props) => React.createElement(View, props);
module.exports = { __esModule: true, default: Stub, SvgXml: Stub, Svg: Stub };
