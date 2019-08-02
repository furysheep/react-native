//
//  Copyright © 2016-2019 PSPDFKit GmbH. All rights reserved.
//
//  THIS SOURCE CODE AND ANY ACCOMPANYING DOCUMENTATION ARE PROTECTED BY INTERNATIONAL COPYRIGHT LAW
//  AND MAY NOT BE RESOLD OR REDISTRIBUTED. USAGE IS BOUND TO THE PSPDFKIT LICENSE AGREEMENT.
//  UNAUTHORIZED REPRODUCTION OR DISTRIBUTION IS SUBJECT TO CIVIL AND CRIMINAL PENALTIES.
//  This notice may not be removed from this file.
//

#import "RCTPSPDFKitManager.h"

#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <React/RCTConvert.h>

#define PROPERTY(property) NSStringFromSelector(@selector(property))

@import PSPDFKit;
@import PSPDFKitUI;

@interface RCTPSPDFKitManager () <PSPDFFormSubmissionDelegate>

@end

@implementation RCTPSPDFKitManager
{
  bool hasListeners;
  PSPDFDocument *currentDocument;
}

RCT_EXPORT_MODULE(PSPDFKit)

RCT_EXPORT_METHOD(setLicenseKey:(NSString *)licenseKey) {
  [PSPDFKit setLicenseKey:licenseKey];
}

RCT_EXPORT_METHOD(present:(PSPDFDocument *)document withConfiguration:(PSPDFConfiguration *)configuration withFields:(NSDictionary *)fields) {
  NSDictionary<PSPDFDocumentPageNumber, NSArray<__kindof PSPDFAnnotation *> *> *annotations = [document allAnnotationsOfType:PSPDFAnnotationTypeWidget];
  currentDocument = document;
  for (PSPDFDocumentPageNumber pageNumber in annotations.allKeys) {
    for (PSPDFFormElement *formElement in annotations[pageNumber]) {
      if ([formElement isKindOfClass:PSPDFTextFieldFormElement.class] && [fields.allKeys indexOfObject:formElement.fieldName] != NSNotFound) {
        formElement.contents = fields[formElement.fieldName];
      }
    }
  }
  
  PSPDFViewController *pdfViewController = [[PSPDFViewController alloc] initWithDocument:document configuration:configuration];
  pdfViewController.formSubmissionDelegate = self;
  pdfViewController.navigationItem.title = @"Form";
  UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:pdfViewController];
  
  UIViewController *presentingViewController = RCTPresentedViewController();
  [presentingViewController presentViewController:navigationController animated:YES completion:nil];
}

RCT_EXPORT_METHOD(dismiss) {
  UIViewController *presentedViewController = RCTPresentedViewController();
  NSAssert([presentedViewController isKindOfClass:UINavigationController.class], @"Presented view controller needs to be a UINavigationController");
  UINavigationController *navigationController = (UINavigationController *)presentedViewController;
  NSAssert(navigationController.viewControllers.count == 1 && [navigationController.viewControllers.firstObject isKindOfClass:PSPDFViewController.class], @"Presented view controller needs to contain a PSPDFViewController");
  [navigationController dismissViewControllerAnimated:true completion:nil];
}

RCT_EXPORT_METHOD(setPageIndex:(NSUInteger)pageIndex animated:(BOOL)animated) {
  UIViewController *presentedViewController = RCTPresentedViewController();
  NSAssert([presentedViewController isKindOfClass:UINavigationController.class], @"Presented view controller needs to be a UINavigationController");
  UINavigationController *navigationController = (UINavigationController *)presentedViewController;
  NSAssert(navigationController.viewControllers.count == 1 && [navigationController.viewControllers.firstObject isKindOfClass:PSPDFViewController.class], @"Presented view controller needs to contain a PSPDFViewController");
  PSPDFViewController *pdfViewController = (PSPDFViewController *)navigationController.viewControllers.firstObject;
  
  [pdfViewController setPageIndex:pageIndex animated:animated];
}

- (dispatch_queue_t)methodQueue {
  return dispatch_get_main_queue();
}

- (NSDictionary *)constantsToExport {
  return @{PROPERTY(versionString): PSPDFKit.versionString,
           PROPERTY(versionNumber): PSPDFKit.versionNumber,
           PROPERTY(buildNumber): @(PSPDFKit.buildNumber)};
}

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

// Will be called when this module's first listener is added.
-(void)startObserving {
  hasListeners = YES;
}

// Will be called when this module's last listener is removed, or on dealloc.
-(void)stopObserving {
  hasListeners = NO;
}

// MARK: - PSPDFFormSubmissionDelegate
- (BOOL)formSubmissionControllerShouldPresentResponseInWebView:(PSPDFFormSubmissionController *)formSubmissionController {
  return NO;
}

- (void)showAlert:(NSString *)fieldName {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:[fieldName stringByAppendingString:@" is required"] preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  
  UIViewController *presentedViewController = RCTPresentedViewController();
  NSAssert([presentedViewController isKindOfClass:UINavigationController.class], @"Presented view controller needs to be a UINavigationController");
  UINavigationController *navigationController = (UINavigationController *)presentedViewController;
  NSAssert(navigationController.viewControllers.count == 1 && [navigationController.viewControllers.firstObject isKindOfClass:PSPDFViewController.class], @"Presented view controller needs to contain a PSPDFViewController");
  PSPDFViewController *pdfViewController = (PSPDFViewController *)navigationController.viewControllers.firstObject;
  [pdfViewController presentViewController:alert animated:YES completion:nil];
}

- (BOOL)formSubmissionController:(PSPDFFormSubmissionController *)formSubmissionController shouldSubmitFormRequest:(PSPDFFormRequest *)formRequest {
  NSDictionary<PSPDFDocumentPageNumber, NSArray<__kindof PSPDFAnnotation *> *> *annotations = [currentDocument allAnnotationsOfType:PSPDFAnnotationTypeWidget];
  
  for (PSPDFDocumentPageNumber pageNumber in annotations.allKeys) {
    for (PSPDFFormElement *formElement in annotations[pageNumber]) {
      if ([formElement isRequired]) {
        if ([formElement isKindOfClass:[PSPDFTextFieldFormElement class]]) {
          if (formRequest.formValues[formElement.fieldName] == nil) {
            [self showAlert:formElement.fieldName];
            return NO;
          }
        }
        if ([formElement isKindOfClass:[PSPDFChoiceFormElement class]]) {
          if (formRequest.formValues[formElement.fieldName] == nil) {
            [self showAlert:formElement.fieldName];
            return NO;
          }
        }
        if ([formElement isKindOfClass:[PSPDFButtonFormElement class]]) {
          if ([formRequest.formValues[formElement.fieldName] isEqualToString:@"Off"]) {
            [self showAlert:@"Option"];
            return NO;
          }
        }
        if ([formElement isKindOfClass:[PSPDFSignatureFormElement class]]) {
          if (![(PSPDFSignatureFormElement *)formElement overlappingInkSignature]) {
            [self showAlert:formElement.fieldName];
            return NO;
          }
        }
      }
    }
  }
  
  if (hasListeners) {
    [self sendEventWithName:@"onSubmitForm" body:@{}];
  }
  
  [self dismiss];
  return NO;
}

// MARK: - RCTEventEmitter
- (NSArray<NSString *> *)supportedEvents {
  return @[@"onSubmitForm"];
}

@end

