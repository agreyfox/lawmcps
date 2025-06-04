"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const swagger_ui_express_1 = __importDefault(require("swagger-ui-express"));
const swagger_config_1 = require("./configs/swagger.config");
const app = (0, express_1.default)();
const port = 6655;
app.get('/', (req, res) => {
    res.redirect('/api-docs');
});
app.use('/api-docs', swagger_ui_express_1.default.serve, swagger_ui_express_1.default.setup(swagger_config_1.swaggerDocs, swagger_config_1.swaggerExplorerOptions));
app.listen(port, () => {
    // eslint-disable-next-line no-console
    console.log(`Flowise API documentation server listening on port ${port}`);
});
//# sourceMappingURL=index.js.map