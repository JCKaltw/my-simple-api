exports.handler = async (event) => {
    const currentDate = new Date().toISOString();
    const responseBody = {
      message: 'Hello, World!',
      timestamp: currentDate,
    };
  
    return {
      statusCode: 200,
      body: JSON.stringify(responseBody),
    };
  };